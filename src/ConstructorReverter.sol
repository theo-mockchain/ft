// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract ConstructorReverter {

        uint256 public x;
        
    constructor() {
        revert("Constructor called");
    }



    function setX(uint256 _x) public {
        x = _x;
    }
}