// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

import { L2ERC777 } from "./L2ERC777.sol";

contract L2ERC777Factory {
    bytes32 public constant ERC777_BYTECODE_HASH = keccak256(type(L2ERC777).creationCode);

    function calculateL2ERC777Address(
        address deployer,
        address _l1Token
    ) external pure returns (address calculatedAddress) {
        calculatedAddress = address(uint(keccak256(abi.encodePacked(
            byte(0xff),
            deployer,
            bytes32(uint(_l1Token)),
            ERC777_BYTECODE_HASH
        ))));
    }

    function deployERC777(address _l1Token) external {
        new L2ERC777{ salt: bytes32(uint(_l1Token)) }();
    }
}
