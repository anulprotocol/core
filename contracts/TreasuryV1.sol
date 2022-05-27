// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract TreasuryV1 is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    uint256 private _nounce;
    uint256 private _deadline;
    uint24 private _bps;
    bool private _burnable;
    bool private _swappable;
    bool private _transferable;

    mapping(address => uint256) public totalBurned;
    mapping(address => ReservedAsset) public reservedAssets;

    struct ReservedAsset {
        uint24 share;
        uint256 swapFee;
        uint256 burnFee;
        bool swappable;
        bool burnable;
        bool ibcable;
    }

    struct Pool {
        uint24 fee;
        address token;
    }

    IERC20 private treasuryAsset;
    IUniswapV2Router02 private routerV2;

    event AssetBurn(address asset, uint256 amount);

    function initialize() public initializer {
        __Ownable_init_unchained();
        _deadline = 10 minutes;
        _bps = 10_000;
    }

    modifier canSwap() {
        require(_swappable, "Cannot swap");
        _;
    }

    modifier canBurn() {
        require(_burnable, "Cannot burn");
        _;
    }

    modifier canTransfer() {
        require(_transferable, "Cannot transfer");
        _;
    }

    function setDeadline(uint256 deadline_) public onlyOwner {
        _deadline = deadline_;
    }

    function setSwappable(bool swappable_) public onlyOwner {
        _swappable = swappable_;
    }

    function setBurnable(bool burnable_) public onlyOwner {
        _burnable = burnable_;
    }

    function setReservedAsset(
        address assetAddr_,
        ReservedAsset calldata reservedAsset_
    ) public onlyOwner {
        require(
            reservedAsset_.share > 0 && reservedAsset_.share <= 100 * _bps,
            "Invalid share"
        );
        require(reservedAsset_.swapFee > 0, "Invalid swap fee");
        require(reservedAsset_.burnFee > 0, "Invalid burn fee");
        reservedAssets[assetAddr_] = reservedAsset_;
    }

    function deleteReservedAsset(address assetAddr_) public onlyOwner {
        delete reservedAssets[assetAddr_];
    }

    function setTreasuryAsset(IERC20 treasuryAsset_) public onlyOwner {
        treasuryAsset = treasuryAsset_;
    }

    function setRouterV2(IUniswapV2Router02 routerV2_) public onlyOwner {
        routerV2 = routerV2_;
    }

    function swapForAssetV1(bytes calldata path_) external canSwap {
        // get first & last token
        address[] memory _path = abi.decode(path_, (address[]));
        require(path_.length > 1, "Bad request");
        address _token0 = _path[0];
        address _tokenX = _path[_path.length - 1];

        // check first & last token
        require(
            address(treasuryAsset) == _token0,
            "Must start by treasury asset"
        );
        ReservedAsset memory _reservedAsset = reservedAssets[_tokenX];
        require(_reservedAsset.swappable, "Not in swap list");
        require(treasuryAsset.balanceOf(address(this)) > 0, "Empty treasury");

        // Swapping fee, user must deposit treasury asset to take action
        uint256 _fee = _reservedAsset.swapFee;
        checkFee(_fee);
        treasuryAsset.transferFrom(msg.sender, address(this), _fee);

        // get swappable amount
        uint256 swappableAmount = getSwapAmount(_reservedAsset.share);
        require(
            treasuryAsset.approve(address(routerV2), swappableAmount),
            "Approval failed"
        );

        // swap then send all asset to treasury
        if (routerV2.WETH() == _tokenX) {
            routerV2.swapExactTokensForETHSupportingFeeOnTransferTokens(
                swappableAmount,
                0,
                _path,
                address(this),
                block.timestamp + _deadline
            );
        } else {
            routerV2.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                swappableAmount,
                0,
                _path,
                address(this),
                block.timestamp + _deadline
            );
        }

        // burn fee
        burnERC20(treasuryAsset, _fee);
    }

    function burn(address assetAddr_) external canBurn {
        // check in reserved list
        ReservedAsset memory _reservedAsset = reservedAssets[assetAddr_];
        require(_reservedAsset.burnable, "Not in burn list");

        // Burning fee, user must deposit treasury asset to take action
        uint256 _fee = _reservedAsset.burnFee;
        checkFee(_fee);
        treasuryAsset.transferFrom(msg.sender, address(this), _fee);

        IERC20 burnAsset = IERC20(assetAddr_);
        uint256 burnAmount = IERC20(assetAddr_).balanceOf(address(this));

        // burn & stat
        burnERC20(burnAsset, burnAmount);
        burnERC20(treasuryAsset, _fee);
    }

    function checkFee(uint256 fee_) internal view {
        // Checking fee, user must deposit treasury asset to take action
        uint256 _allowanceAmount = treasuryAsset.allowance(
            msg.sender,
            address(this)
        );
        require(_allowanceAmount >= fee_, "Require more ANUL");
    }

    function getSwapAmount(uint24 share_) internal view returns (uint256) {
        return
            treasuryAsset.balanceOf(address(this)).mul(share_).div(100 * _bps);
    }

    function burnERC20(IERC20 asset_, uint256 amount_) internal {
        // update stat
        totalBurned[address(asset_)] = totalBurned[address(asset_)].add(
            amount_
        );
        // burn
        require(asset_.transfer(address(1), amount_), "Burn failed");

        emit AssetBurn(address(asset_), amount_);
    }

    // saved method to withdraw ETH if any
    function withdraw(address recipient_) public payable onlyOwner {
        payable(recipient_).transfer(address(this).balance);
    }
}
