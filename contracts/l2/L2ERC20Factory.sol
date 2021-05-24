// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

import { L2ERC20 } from "./L2ERC20.sol";

contract L2ERC20Factory {
    bytes32 public constant ERC20_BYTECODE_HASH = keccak256(type(L2ERC20).creationCode);

    function calculateL2ERC20Address(
        address deployer,
        address _l1Token
    ) external pure returns (address calculatedAddress) {
        calculatedAddress = address(uint(keccak256(abi.encodePacked(
            byte(0xff),
            deployer,
            bytes32(uint(_l1Token)),
            ERC20_BYTECODE_HASH
        ))));
    }

    function deployERC20(address _l1Token) external {
        new L2ERC20{ salt: bytes32(uint(_l1Token)) }();
    }
}
