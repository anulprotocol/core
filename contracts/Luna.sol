// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Luna is ERC20 {

    constructor(string memory name_, string memory symbol_) public ERC20(name_, symbol_) {
        _mint(msg.sender, 1_000_000_000 ether);
    }

}
