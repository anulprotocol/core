// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract Anul is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 private _cap;
    uint24 private _buyingTax;
    uint24 private _sellingTax;
    uint24 private _bps;
    address private _treasury;
    address[] private _whitelist;

    modifier nonZeroAddr(address addr) {
        require(addr != address(0), "Address must not be zero");
        _;
    }

    modifier taxable(uint256 tax) {
        require(tax > 0, "Tax is too low");
        require(tax < 100 * _bps, "Tax is too high");
        _;
    }

    constructor(string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;

        _cap = 100_000_000_000 ether;
        _buyingTax = 70_000;
        _sellingTax = 150_000;
        _bps = 10_000;
        _whitelist = [msg.sender, address(0), address(1)];

        _mint(msg.sender, _cap);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function setBuyingTax(uint24 buyingTax_)
        public
        onlyOwner
        taxable(buyingTax_)
    {
        _buyingTax = buyingTax_;
    }

    function getBuyingTax() external view returns (uint24) {
        return _buyingTax;
    }

    function setSellingTax(uint24 sellingTax_)
        public
        onlyOwner
        taxable(sellingTax_)
    {
        _sellingTax = sellingTax_;
    }

    function getSellingTax() external view returns (uint24) {
        return _sellingTax;
    }

    function setTreasury(address treasury_)
        public
        onlyOwner
        nonZeroAddr(treasury_)
    {
        _treasury = treasury_;
    }

    function addWhitelist(address target_)
        public
        onlyOwner
        nonZeroAddr(target_)
    {
        (bool found,) = findWhitelist(target_);
        if (!found) {
            _whitelist.push(target_);
        }
    }

    function removeWhitelist(address target_)
        public
        onlyOwner
        nonZeroAddr(target_)
    {
        (bool found, uint256 index) = findWhitelist(target_);
        if (found) {
            _whitelist[index] = _whitelist[_whitelist.length - 1];
            _whitelist.pop();
        }
    }

    function findWhitelist(address target_)
        internal
        virtual
        returns (bool found, uint256 index)
    {
        uint256 size = _whitelist.length;
        found = false;
        index = 0;
        for (uint256 i = 0; i < size; i++) {
            if (_whitelist[i] == target_) {
                found = true;
                index = i;
                break;
            }
        }
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        // apply tax
        uint256 transferAmount = amount;
        uint256 taxAmount = 0;
        // exclude minting, add liquidity
        // exclude sending to treasury for burning
        (bool senderInWhitelist,) = findWhitelist(sender);
        (bool recipientInWhitelist,) = findWhitelist(
            recipient
        );
        if (!senderInWhitelist && !recipientInWhitelist) {
            taxAmount = amount
                .mul(sender.isContract() ? _sellingTax : _buyingTax)
                .div(100 * _bps);
            transferAmount = transferAmount.sub(taxAmount);
        }

        _balances[sender] = _balances[sender].sub(
            amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[recipient] = _balances[recipient].add(transferAmount);

        // add treasury
        if (taxAmount > 0) {
            _balances[_treasury] = _balances[_treasury].add(taxAmount);
        }
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(
            amount,
            "ERC20: burn amount exceeds balance"
        );
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimals = decimals_;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        if (from == address(0)) {
            // When minting tokens
            require(
                totalSupply().add(amount) <= _cap,
                "ERC20Capped: cap exceeded"
            );
        }
    }
}
