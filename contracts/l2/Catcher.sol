// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Interface Imports */
// import { iOVM_L2DepositedToken } from "../../../iOVM/bridge/tokens/iOVM_L2DepositedToken.sol";
// import { iOVM_L1TokenGateway } from "../../../iOVM/bridge/tokens/iOVM_L1TokenGateway.sol";

/* Library Imports */
import { OVM_CrossDomainEnabled } from "../libraries/OVM_CrossDomainEnabled.sol";

/**
 * @title Abs_L2DepositedToken
 * @dev An L2 Deposited Token is an L2 representation of funds which were deposited from L1.
 * Usually contract mints new tokens when it hears about deposits into the L1 ERC20 gateway.
 * This contract also burns the tokens intended for withdrawal, informing the L1 gateway to release L1 funds.
 *
 * NOTE: This abstract contract gives all the core functionality of a deposited token implementation except for the
 * token's internal accounting itself.  This gives developers an easy way to implement children with their own token code.
 *
 * Compiler used: optimistic-solc
 * Runtime target: OVM
 */
contract Catcher is OVM_CrossDomainEnabled {
    bytes public lastCall;
    address public lastSender;

    /**
     * @param _l2CrossDomainMessenger L1 Messenger address being used for cross-chain communications.
     */
    constructor(
        address _l2CrossDomainMessenger
    )
        OVM_CrossDomainEnabled(_l2CrossDomainMessenger)
    {}

    fallback() external {
        lastCall = msg.data;
        lastSender = msg.sender;
    }
}
