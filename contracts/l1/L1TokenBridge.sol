// SPDX-License-Identifier: MIT
// @unsupported: ovm 
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Interface Imports */
import { IL1TokenBridge } from "../interfaces/IL1TokenBridge.sol";
import { IL2TokenBridge } from "../interfaces/IL2TokenBridge.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/* Library Imports */
import { OVM_CrossDomainEnabled } from "@eth-optimism/contracts/build/contracts/libraries/bridge/OVM_CrossDomainEnabled.sol";
import { SafeERC20Namer } from "@uniswap/lib/contracts/libraries/SafeERC20Namer.sol";
import { TransferHelper } from "@uniswap/lib/contracts/libraries/TransferHelper.sol";

/**
 * @title L1TokenBridge
 * @dev The L1 Token Bridge is a contract which stores deposited L1 funds that are in use on L2.
 * It synchronizes a corresponding L2 ERC20 Bridge, informing it of deposits, and listening to it 
 * for newly finalized withdrawals.
 *
 * Compiler used: solc
 * Runtime target: EVM
 */
contract L1TokenBridge is IL1TokenBridge, OVM_CrossDomainEnabled {
    /********************************
     * External Contract References *
     ********************************/

    address public immutable l2Bridge;
    bytes32 public immutable l2ERC20BytecodeHash;
    bytes32 public immutable l2ERC777BytecodeHash;

    uint32 public DEFAULT_FINALIZE_DEPOSIT_L2_GAS = 4000000;

    /***************
     * Constructor *
     ***************/

    /**
     * @param _l2Bridge L2 bridge contract address
     * @param _l1messenger L1 Messenger address being used for cross-chain communications.
     * @param _l2ERC20BytecodeHash Hash of the L2 ERC20 contract bytecode, used to calculate token addresses
     * @param _l2ERC777BytecodeHash Hash of the L2 ERC777 contract bytecode, used to calculate token addresses
     */
    constructor(
        address _l2Bridge,
        address _l1messenger,
        bytes32 _l2ERC20BytecodeHash,
        bytes32 _l2ERC777BytecodeHash
    )
        OVM_CrossDomainEnabled(_l1messenger)
    {
        l2Bridge = _l2Bridge;
        l2ERC20BytecodeHash = _l2ERC20BytecodeHash;
        l2ERC777BytecodeHash = _l2ERC777BytecodeHash;
    }

    /**********************
     * L2 Token Addresses *
     **********************/

    /**
     * Calculates the addres of a bridged ERC777 on L2
     * @param _l1Token The ERC20 token on L1
     * @return calculatedAddress The address of the bridged ERC777 on L2
     */
    function calculateL2ERC777Address(address _l1Token) public view returns (address calculatedAddress) {
        calculatedAddress = address(uint(keccak256(abi.encodePacked(
            byte(0xff),
            l2Bridge,
            bytes32(uint(_l1Token)),
            l2ERC777BytecodeHash
        ))));
    }

    /**
     * Calculates the addres of a bridged ERC20 on L2
     * @param _l1Token The ERC20 token on L1
     * @return calculatedAddress The address of the bridged ERC20 on L2
     */
    function calculateL2ERC20Address(address _l1Token) public view returns (address calculatedAddress) {
        calculatedAddress = address(uint(keccak256(abi.encodePacked(
            byte(0xff),
            l2Bridge,
            bytes32(uint(_l1Token)),
            l2ERC20BytecodeHash
        ))));
    }

    /**************
     * Depositing *
     **************/

    /**
     * @dev deposit an amount of ERC20 to a recipients's balance on L2
     * @param _to L2 address to credit the withdrawal to
     * @param _amount Amount of the ERC20 to deposit
     */
    function depositAsERC20(
        address token,
        address _to,
        uint _amount
    )
        external
        override
    {
        _initiateDeposit(IL2TokenBridge.depositAsERC20.selector, token, msg.sender, _to, _amount);
    }

    /**
     * @dev deposit an amount of ERC20 to a recipients's balance on L2
     * @param _to L2 address to credit the withdrawal to
     * @param _amount Amount of the ERC20 to deposit
     */
    function depositAsERC777(
        address _token,
        address _to,
        uint _amount
    )
        external
        override
    {
        require(ERC20(_token).decimals() <= 18, "Decimals");
        _initiateDeposit(IL2TokenBridge.depositAsERC777.selector, _token, msg.sender, _to, _amount);
    }

    /**
     * @dev Performs the logic for deposits by storing the ERC20 and informing the L2 Deposited ERC20 contract of the deposit.
     *
     * @param _from Account to pull the deposit from on L1
     * @param _to Account to give the deposit to on L2
     * @param _amount Amount of the ERC20 to deposit.
     */
    function _initiateDeposit(
        bytes4 _selector,
        address _token,
        address _from,
        address _to,
        uint _amount
    )
        internal
    {
        // Hold on to the newly deposited funds
        uint256 startingBalance = ERC20(_token).balanceOf(address(this));
        TransferHelper.safeTransferFrom(_token, _from, address(this), _amount);
        uint256 transferedAmount = ERC20(_token).balanceOf(address(this)) - startingBalance;

        uint8 _decimals = ERC20(_token).decimals();

        // Construct calldata for l2Bridge.finalizeDeposit(_to, _amount)
        bytes memory data = abi.encodeWithSelector(_selector, _token, _to, transferedAmount, _decimals);

        // Send calldata into L2
        sendCrossDomainMessage(
            l2Bridge,
            data,
            DEFAULT_FINALIZE_DEPOSIT_L2_GAS
        );

        emit DepositInitiated(_token, _from, _to, _amount);
    }

    /**
     * @dev L2 tokens have no name or symbol by default. This function passes that data to L2.
     * @param _l1Token Address of the L1 token
     */
    function updateTokenInfo(address _l1Token) external {
        bytes memory data = abi.encodeWithSelector(
            IL2TokenBridge.updateTokenInfo.selector,
            _l1Token,
            SafeERC20Namer.tokenName(_l1Token),
            SafeERC20Namer.tokenSymbol(_l1Token)
        );
        sendCrossDomainMessage(l2Bridge, data, DEFAULT_FINALIZE_DEPOSIT_L2_GAS);
    }

    /*************************************
     * Cross-chain Function: Withdrawing *
     *************************************/

    /**
     * @dev Complete a withdrawal from L2 to L1, and credit funds to the recipient's balance of the 
     * L1 ERC20 token. 
     * This call will fail if the initialized withdrawal from L2 has not been finalized. 
     *
     * @param _to L1 address to credit the withdrawal to
     * @param _amount Amount of the ERC20 to withdraw
     */
    function finalizeWithdrawal(
        address _token,
        address _to,
        uint _amount
    )
        external
        override 
        onlyFromCrossDomainAccount(l2Bridge)
    {
        TransferHelper.safeTransfer(_token, _to, _amount);

        emit WithdrawalFinalized(_token, _to, _amount);
    }
}
