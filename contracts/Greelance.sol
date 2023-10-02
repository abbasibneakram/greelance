// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Greelance is IERC20, Ownable {

    string public name = "Greelance";
    string public symbol = "GRL";
    uint8 public decimals = 9;
    uint256 public totalSupply = 2000000000 * 10**uint256(decimals);

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Maximum sellable amount for 24 hours
    uint256 public maxSellableAmount= 1000*10**9;
    bool public maxSellableRestrictionEnabled = true; // Default to enabled

    // Trading status
    bool public tradingPaused = true;
    bool public trading24HrsRestrictionEnabled = true; // Default to enabled
    mapping(address=>uint256) public lastTradeTime;

    //tax status
    uint256 buyTaxPercentage = 5;
    uint256 sellTaxPercentage = 5;
    address immutable taxCollector;
    bool taxDeductionEnabled = false;
    mapping(address=>bool) public taxExemptWallet;
    address uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Reentrancy guard
    bool private _notEntered = true;

    modifier nonReentrant() {
        require(_notEntered, "ReentrancyGuard: reentrant call");
        _notEntered = false;
        _;
        _notEntered = true;
    }

    constructor() {
        _balances[msg.sender] = totalSupply;
        taxCollector = owner();
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender]-amount
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender]+addedValue
        );
        return true;
    }

  function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        returns (bool)
    {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(
            currentAllowance >= subtractedValue,
            "Allowance insufficient"
        );
        _approve(
            msg.sender,
            spender,
            currentAllowance-subtractedValue
        );
        return true;
    }

    function _updateBalances( address sender,address recipient,uint256 amount) internal{
        _balances[sender] = _balances[sender]-amount;
        _balances[recipient] = _balances[recipient]+amount;
        lastTradeTime[sender] = block.timestamp;
    }


    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal nonReentrant {
        require(tradingPaused == false, "Trading is paused");
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(_balances[sender] >= amount, "Insufficient balance");

        uint256 taxRate = sender == uniswapRouterAddress ? buyTaxPercentage : sellTaxPercentage;
        uint256 taxAmount = 0;
        if (maxSellableRestrictionEnabled){
            taxAmount = (maxSellableAmount * taxRate) / 100;
        }
        else{
            taxAmount = (amount * taxRate) / 100;
        }
        if(taxDeductionEnabled && !taxExemptWallet[sender] && trading24HrsRestrictionEnabled && maxSellableRestrictionEnabled){
            require(block.timestamp-lastTradeTime[sender] >= 1 days,
            "Transfer restricted before 24 hours");
                if(amount > maxSellableAmount){
                    _updateBalances(sender,recipient,maxSellableAmount-taxAmount);
                    _balances[taxCollector] = _balances[taxCollector]+taxAmount;
                }
                else{
                     _updateBalances(sender,recipient,amount-taxAmount);
                     _balances[taxCollector] = _balances[taxCollector]+taxAmount;
                }
        }
        else if(taxDeductionEnabled && !taxExemptWallet[sender] && trading24HrsRestrictionEnabled && !maxSellableRestrictionEnabled){
            require(block.timestamp-lastTradeTime[sender] >= 1 days,
            "Transfer restricted before 24 hours");
            _updateBalances(sender,recipient,amount-taxAmount);
            _balances[taxCollector] = _balances[taxCollector]+taxAmount;
        }
        else if(taxDeductionEnabled && !taxExemptWallet[sender] && !trading24HrsRestrictionEnabled && maxSellableRestrictionEnabled){
            if(amount > maxSellableAmount){
                    _updateBalances(sender,recipient,maxSellableAmount-taxAmount);
                    _balances[taxCollector] = _balances[taxCollector]+taxAmount;
            }
            else{
                _updateBalances(sender,recipient,amount-taxAmount);
                _balances[taxCollector] = _balances[taxCollector]+taxAmount;
            }
        }
        else if(taxDeductionEnabled && !taxExemptWallet[sender]){
            _updateBalances(sender,recipient,amount-taxAmount);
            _balances[taxCollector] = _balances[taxCollector]+taxAmount;
        }
        else if(!trading24HrsRestrictionEnabled && maxSellableRestrictionEnabled){
            if(amount > maxSellableAmount){
                    _updateBalances(sender,recipient,maxSellableAmount);
            }
            else{
                _updateBalances(sender,recipient,amount);
            }
        }
        else if(trading24HrsRestrictionEnabled && !maxSellableRestrictionEnabled){
            require(block.timestamp-lastTradeTime[sender] >= 1 days,
            "Transfer restricted before 24 hours");
            _updateBalances(sender,recipient,amount);
        } 

        else{
            _updateBalances(sender,recipient,amount);
        }
        emit Transfer(sender, recipient, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Function to set the maximum sellable amount (only callable by the owner)
    function setMaxSellableAmount(uint256 _maxAmount) external onlyOwner {
        maxSellableAmount = _maxAmount;
    }

    function setBuyTaxAmount(uint256 _taxAmount) external onlyOwner {
        buyTaxPercentage = _taxAmount;
    }

     function setSellTaxAmount(uint256 _taxAmount) external onlyOwner {
        sellTaxPercentage = _taxAmount;
    }

    // Function to enable tax deduction (only callable by the owner)
    function enableTaxDeduction() external onlyOwner {
        taxDeductionEnabled = true;
    }

    // Function to disable tax deduction (only callable by the owner)
    function removeTaxDeduction() external onlyOwner {
        taxDeductionEnabled = false;
    }

    // Function to exclude a wallet from tax (only callable by the owner)
    function excludeFromTax(address account) external onlyOwner {
        taxExemptWallet[account] = true;
    } 
    // Function to disable maximum sellable amount restriction (only callable by the owner)
    function removeMaxSellableRestriction() external onlyOwner {
        maxSellableRestrictionEnabled = false;
    }

    // Function to enable the 24-hour trading restriction (only callable by the owner)
    function enable24HrsRestriction() external onlyOwner {
        trading24HrsRestrictionEnabled = true;
    }

    // Function to disable the 24-hour trading restriction (only callable by the owner)
    function disable24HrsRestriction() external onlyOwner {
        trading24HrsRestrictionEnabled = false;
    }

    // Function to start or pause trading (only callable by the owner)
    function setTradingStatus(bool _paused) external onlyOwner {
        tradingPaused = _paused;
    }

    function setUniswapRouterAddress(address _router) external onlyOwner {
        uniswapRouterAddress = _router;
    }
}