// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Interface Imports */
import { IL1TokenBridge } from "../interfaces/IL1TokenBridge.sol";
import { IL2TokenBridge } from "../interfaces/IL2TokenBridge.sol";
import { IL2Token } from "../interfaces/IL2Token.sol";

/* Contract Imports */
import { L2ERC20Factory } from "./L2ERC20Factory.sol";
import { L2ERC777Factory } from "./L2ERC777Factory.sol";

/* Library Imports */
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { OVM_CrossDomainEnabled } from "@eth-optimism/contracts/build/contracts/libraries/bridge/OVM_CrossDomainEnabled.sol";

/**
 * @title OVM_L2TokenBridge
 * @dev The L1 ERC20 Gateway is a contract which stores deposited L1 funds that are in use on L2.
 * It synchronizes a corresponding L2 ERC20 Gateway, informing it of deposits, and listening to it 
 * for newly finalized withdrawals.
 *
 * Compiler used: solc
 * Runtime _target: EVM
 */
contract L2TokenBridge is IL2TokenBridge, OVM_CrossDomainEnabled {
    using Address for address;

    /*******************
     * Contract Events *
     *******************/

    event Initialized(IL1TokenBridge _l1TokenBridge);

    /********************************
     * External Contract References *
     ********************************/

    IL1TokenBridge l1TokenBridge;

    L2ERC20Factory public immutable erc20Factory;
    L2ERC777Factory public immutable erc777Factory;

    uint32 constant DEFAULT_FINALIZE_WITHDRAWAL_L1_GAS = 100000;

    /********************************
     * Constructor & Initialization *
     ********************************/

    /**
     * @param _l2CrossDomainMessenger L1 Messenger address being used for cross-chain communications.
     */
    constructor(
        address _erc20Factory,
        address _erc777Factory,
        address _l2CrossDomainMessenger
    )
        public
        OVM_CrossDomainEnabled(_l2CrossDomainMessenger)
    {
        erc20Factory = L2ERC20Factory(_erc20Factory);
        erc777Factory = L2ERC777Factory(_erc777Factory);
    }

    /**
     * @dev Initialize this gateway with the L1 gateway address
     * The assumed flow is that this contract is deployed on L2, then the L1 
     * gateway is dpeloyed, and its address passed here to init.
     *
     * @param _l1TokenBridge Address of the corresponding L1 gateway deployed to the main chain
     */
    function init(
        IL1TokenBridge _l1TokenBridge
    )
        external
    {
        require(address(l1TokenBridge) == address(0), "Contract has already been initialized");

        l1TokenBridge = _l1TokenBridge;
        
        emit Initialized(l1TokenBridge);
    }

    /**********************
     * Function Modifiers *
     **********************/

    modifier onlyInitialized() {
        // require(address(l1TokenBridge) != address(0), "Contract has not yet been initialized");
        _;
    }

    function calculateL2ERC777Address(address _l1Token) public view returns (address) {
        return erc777Factory.calculateL2ERC777Address(address(this), _l1Token);
    }

    function calculateL2ERC20Address(address _l1Token) public view returns (address) {
        return erc20Factory.calculateL2ERC20Address(address(this), _l1Token);
    }

    /***************
     * Withdrawing *
     ***************/

    /**
     * @dev Called by a L2 token to withdraw tokens back to L1
     * @param _l1Token Address of the token on L1
     * @param _destination Address to receive tokens on L1
     * @param _amount Amount of the ERC20 to withdraw
     */
    function withdraw(
        address _l1Token,
        address _destination,
        uint _amount
    )
        external
        override
    {
        require(msg.sender == calculateL2ERC777Address(_l1Token)
            || msg.sender == calculateL2ERC20Address(_l1Token),
            "Must be called by a bridged token");

        // Construct calldata for bridge.finalizeWithdrawal(_to, _amount)
        bytes memory data = abi.encodeWithSelector(
            IL1TokenBridge.finalizeWithdrawal.selector,
            _l1Token,
            _destination,
            _amount
        );

        // Send message up to L1 gateway
        sendCrossDomainMessage(
            address(l1TokenBridge),
            data,
            DEFAULT_FINALIZE_WITHDRAWAL_L1_GAS
        );

        emit WithdrawalInitiated(_l1Token, msg.sender, _destination, _amount);
    }

    /**
     * @dev Allows converting betwen ERC20 & ERC777 tokens. Must be called by token.
     * @param _l1Token Address of the token on L1
     * @param _recipient Address to receive tokens
     * @param _target The token to migrate to
     * @param _amount Amount of the ERC20 to migrate (in ERC20 decimals)
     */
    function migrate(
        address _l1Token,
        address _target,
        address _recipient,
        uint256 _amount
    ) external override {
        address l2ERC777 = calculateL2ERC777Address(_l1Token);
        address l2ERC20 = calculateL2ERC20Address(_l1Token);

        require(msg.sender == l2ERC777 || msg.sender == l2ERC20, "Must be called by token");
        require(_target == l2ERC777 || _target == l2ERC20, "Can only migrate to ERC20 or ERC777");

        IL2Token(_target).mint(_recipient, _amount);
    }

    /************************************
     * Cross-chain Function: Depositing *
     ************************************/

    /**
     * @dev Complete a deposit from L1 to L2, and credits funds to the recipient's balance of this 
     * L2 ERC20 token. 
     * This call will fail if it did not originate from a corresponding deposit in OVM_L1ERC20Gateway. 
     *
     * @param _to Address to receive the withdrawal at
     * @param _amount Amount of the ERC20 to withdraw
     */
    function depositAsERC20(
        address _token,
        address _to,
        uint _amount,
        uint8 _decimals
    ) external override onlyInitialized /*onlyFromCrossDomainAccount(address(l1TokenBridge))*/
    {
        IL2Token l2Token = getToken(_token, _decimals, false);
        l2Token.mint(_to, _amount);
        emit DepositFinalized(_token, _to, _amount);
    }

    function depositAsERC777(
        address _token,
        address _to,
        uint _amount,
        uint8 _decimals
    ) external override onlyInitialized /*onlyFromCrossDomainAccount(address(l1TokenBridge))*/
    {
        IL2Token l2Token = getToken(_token, _decimals, true);
        l2Token.mint(_to, _amount);
        emit DepositFinalized(_token, _to, _amount);
    }

    function updateTokenInfo(
        address l1ERC20,
        string calldata name,
        string calldata symbol
    ) external override onlyInitialized /*onlyFromCrossDomainAccount(address(l1TokenBridge))*/ {
        address erc777 = calculateL2ERC777Address(l1ERC20);
        address erc20 = calculateL2ERC20Address(l1ERC20);

        if (erc777.isContract()) {
            IL2Token(erc777).updateInfo(name, symbol);
        }
        if (erc20.isContract()) {
            IL2Token(erc20).updateInfo(name, symbol);
        }
    }

    function getToken(address _l1Token, uint8 decimals, bool isERC777) private returns (IL2Token) {
        address calculatedAddress = isERC777
            ? calculateL2ERC777Address(_l1Token)
            : calculateL2ERC20Address(_l1Token);

        if (!calculatedAddress.isContract()) {
            if (isERC777) {
                deployERC777(_l1Token);
            } else {
                deployERC20(_l1Token);
            }
            IL2Token(calculatedAddress).initialize(_l1Token, decimals);
        }

        return IL2Token(calculatedAddress);
    }

    function deployERC777(address _l1Token) private {
        (bool success, bytes memory returnData) = address(erc777Factory).delegatecall(abi.encodeWithSelector(
            L2ERC777Factory.deployERC777.selector,
            _l1Token
        ));
        require(success, string(returnData));
    }

    function deployERC20(address _l1Token) private {
        (bool success, bytes memory returnData) = address(erc20Factory).delegatecall(abi.encodeWithSelector(
            L2ERC20Factory.deployERC20.selector,
            _l1Token
        ));
        require(success, string(returnData));
    }
}
