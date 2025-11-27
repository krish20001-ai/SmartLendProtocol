// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SmartLend Protocol
 * @dev A decentralized lending and borrowing protocol with collateral management
 * @notice This contract allows users to deposit assets, borrow against collateral, and earn interest
 */
contract Project {
    
    // State Variables
    address public owner;
    uint256 public constant COLLATERAL_RATIO = 150; // 150% collateralization required
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120% liquidation threshold
    uint256 public constant INTEREST_RATE = 5; // 5% annual interest rate (simplified)
    uint256 public constant MAX_LOAN_AMOUNT = 1000 ether;
    
    // Structs
    struct Loan {
        uint256 principal;
        uint256 collateral;
        uint256 timestamp;
        bool active;
        uint256 interestAccrued;
    }
    
    struct UserAccount {
        uint256 deposited;
        uint256 earned;
        bool isLender;
    }
    
    // Mappings
    mapping(address => Loan) public loans;
    mapping(address => UserAccount) public lenders;
    mapping(address => uint256) public lastInterestUpdate;
    
    // Pool variables
    uint256 public totalLiquidity;
    uint256 public totalBorrowed;
    
    // Events
    event Deposited(address indexed lender, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed lender, uint256 amount, uint256 timestamp);
    event LoanCreated(address indexed borrower, uint256 loanAmount, uint256 collateral, uint256 timestamp);
    event LoanRepaid(address indexed borrower, uint256 amount, uint256 timestamp);
    event CollateralAdded(address indexed borrower, uint256 amount, uint256 timestamp);
    event Liquidated(address indexed borrower, uint256 debtCovered, uint256 timestamp);
    event InterestPaid(address indexed borrower, uint256 interest, uint256 timestamp);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier validAddress(address _addr) {
        require(_addr != address(0), "Invalid address");
        require(_addr != address(this), "Cannot use contract address");
        _;
    }
    
    modifier loanExists() {
        require(loans[msg.sender].active, "No active loan found");
        _;
    }
    
    // Reentrancy Guard
    uint256 private locked = 1;
    modifier nonReentrant() {
        require(locked == 1, "Reentrancy detected");
        locked = 2;
        _;
        locked = 1;
    }
    
    // Constructor
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Allows users to deposit funds into the lending pool
     * @notice Depositors earn interest from borrowers
     */
    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        require(msg.value <= type(uint256).max - totalLiquidity, "Liquidity overflow");
        
        lenders[msg.sender].deposited += msg.value;
        lenders[msg.sender].isLender = true;
        totalLiquidity += msg.value;
        
        emit Deposited(msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Allows lenders to withdraw their deposited funds plus earned interest
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(lenders[msg.sender].isLender, "No deposits found");
        require(amount > 0, "Amount must be greater than zero");
        
        uint256 availableBalance = lenders[msg.sender].deposited + lenders[msg.sender].earned;
        require(amount <= availableBalance, "Insufficient balance");
        require(amount <= totalLiquidity - totalBorrowed, "Insufficient liquidity in pool");
        
        // Update state before transfer
        if (amount <= lenders[msg.sender].earned) {
            lenders[msg.sender].earned -= amount;
        } else {
            uint256 fromEarned = lenders[msg.sender].earned;
            uint256 fromDeposited = amount - fromEarned;
            lenders[msg.sender].earned = 0;
            lenders[msg.sender].deposited -= fromDeposited;
        }
        
        totalLiquidity -= amount;
        
        // Transfer after state update (Checks-Effects-Interactions pattern)
        payable(msg.sender).transfer(amount);
        
        emit Withdrawn(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @dev Allows users to borrow funds by providing collateral
     * @param loanAmount The amount to borrow
     * @notice Requires 150% collateralization
     */
    function borrow(uint256 loanAmount) external payable nonReentrant {
        require(!loans[msg.sender].active, "Existing loan must be repaid first");
        require(loanAmount > 0, "Loan amount must be greater than zero");
        require(loanAmount <= MAX_LOAN_AMOUNT, "Exceeds maximum loan amount");
        require(loanAmount <= totalLiquidity - totalBorrowed, "Insufficient liquidity");
        
        // Calculate required collateral (150% of loan amount)
        uint256 requiredCollateral = (loanAmount * COLLATERAL_RATIO) / 100;
        require(msg.value >= requiredCollateral, "Insufficient collateral provided");
        
        // Create loan
        loans[msg.sender] = Loan({
            principal: loanAmount,
            collateral: msg.value,
            timestamp: block.timestamp,
            active: true,
            interestAccrued: 0
        });
        
        lastInterestUpdate[msg.sender] = block.timestamp;
        totalBorrowed += loanAmount;
        totalLiquidity += msg.value; // Collateral added to pool
        
        // Transfer loan amount to borrower
        payable(msg.sender).transfer(loanAmount);
        
        emit LoanCreated(msg.sender, loanAmount, msg.value, block.timestamp);
    }
    
    /**
     * @dev Calculate accrued interest for a borrower
     * @param borrower The address of the borrower
     * @return The accrued interest amount
     */
    function calculateInterest(address borrower) public view returns (uint256) {
        if (!loans[borrower].active) return 0;
        
        uint256 timeElapsed = block.timestamp - lastInterestUpdate[borrower];
        uint256 principal = loans[borrower].principal;
        
        // Simple interest calculation: (principal * rate * time) / (100 * 365 days)
        uint256 interest = (principal * INTEREST_RATE * timeElapsed) / (100 * 365 days);
        
        return loans[borrower].interestAccrued + interest;
    }
    
    /**
     * @dev Update interest for a borrower
     * @param borrower The address of the borrower
     */
    function updateInterest(address borrower) internal {
        if (loans[borrower].active) {
            loans[borrower].interestAccrued = calculateInterest(borrower);
            lastInterestUpdate[borrower] = block.timestamp;
        }
    }
    
    /**
     * @dev Allows borrowers to repay their loan with interest
     */
    function repayLoan() external payable loanExists nonReentrant {
        updateInterest(msg.sender);
        
        uint256 totalDebt = loans[msg.sender].principal + loans[msg.sender].interestAccrued;
        require(msg.value >= totalDebt, "Insufficient repayment amount");
        
        uint256 collateralToReturn = loans[msg.sender].collateral;
        uint256 principal = loans[msg.sender].principal;
        uint256 interest = loans[msg.sender].interestAccrued;
        
        // Update state before transfers
        totalBorrowed -= principal;
        totalLiquidity -= collateralToReturn;
        delete loans[msg.sender];
        
        // Distribute interest to lenders (simplified - goes to pool)
        totalLiquidity += interest;
        
        // Return collateral to borrower
        payable(msg.sender).transfer(collateralToReturn);
        
        // Return excess payment if any
        if (msg.value > totalDebt) {
            payable(msg.sender).transfer(msg.value - totalDebt);
        }
        
        emit LoanRepaid(msg.sender, totalDebt, block.timestamp);
        emit InterestPaid(msg.sender, interest, block.timestamp);
    }
    
    /**
     * @dev Allows borrowers to add more collateral to their loan
     */
    function addCollateral() external payable loanExists nonReentrant {
        require(msg.value > 0, "Collateral amount must be greater than zero");
        
        loans[msg.sender].collateral += msg.value;
        totalLiquidity += msg.value;
        
        emit CollateralAdded(msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Check if a loan is under-collateralized and can be liquidated
     * @param borrower The address of the borrower
     * @return True if the loan can be liquidated
     */
    function isLiquidatable(address borrower) public view returns (bool) {
        if (!loans[borrower].active) return false;
        
        uint256 totalDebt = loans[borrower].principal + calculateInterest(borrower);
        uint256 collateralValue = loans[borrower].collateral;
        
        // Check if collateral ratio falls below liquidation threshold (120%)
        return (collateralValue * 100) < (totalDebt * LIQUIDATION_THRESHOLD);
    }
    
    /**
     * @dev Liquidate an under-collateralized loan
     * @param borrower The address of the borrower to liquidate
     * @notice Anyone can call this function to liquidate under-collateralized loans
     */
    function liquidate(address borrower) external validAddress(borrower) nonReentrant {
        require(loans[borrower].active, "No active loan for this address");
        require(isLiquidatable(borrower), "Loan is sufficiently collateralized");
        
        updateInterest(borrower);
        
        uint256 totalDebt = loans[borrower].principal + loans[borrower].interestAccrued;
        uint256 collateral = loans[borrower].collateral;
        uint256 principal = loans[borrower].principal;
        
        // Update state
        totalBorrowed -= principal;
        totalLiquidity -= collateral;
        totalLiquidity += totalDebt; // Debt covered by collateral
        
        delete loans[borrower];
        
        emit Liquidated(borrower, totalDebt, block.timestamp);
    }
    
    /**
     * @dev Get loan details for a borrower
     * @param borrower The address of the borrower
     * @return principal The loan principal
     * @return collateral The collateral amount
     * @return interest The accrued interest
     * @return active Whether the loan is active
     */
    function getLoanDetails(address borrower) external view returns (
        uint256 principal,
        uint256 collateral,
        uint256 interest,
        bool active
    ) {
        Loan memory loan = loans[borrower];
        return (
            loan.principal,
            loan.collateral,
            calculateInterest(borrower),
            loan.active
        );
    }
    
    /**
     * @dev Get lender account details
     * @param lender The address of the lender
     * @return deposited The amount deposited
     * @return earned The interest earned
     * @return isLender Whether the address is a lender
     */
    function getLenderDetails(address lender) external view returns (
        uint256 deposited,
        uint256 earned,
        bool isLender
    ) {
        UserAccount memory account = lenders[lender];
        return (account.deposited, account.earned, account.isLender);
    }
    
    /**
     * @dev Get protocol statistics
     * @return liquidity Total liquidity in the pool
     * @return borrowed Total amount borrowed
     * @return available Available liquidity for borrowing
     */
    function getProtocolStats() external view returns (
        uint256 liquidity,
        uint256 borrowed,
        uint256 available
    ) {
        return (totalLiquidity, totalBorrowed, totalLiquidity - totalBorrowed);
    }
    
    /**
     * @dev Emergency withdrawal function for owner (use with caution)
     * @notice Only for emergency situations
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Fallback functions
    receive() external payable {
        revert("Use deposit() function to add funds");
    }
    
    fallback() external payable {
        revert("Function does not exist");
    }
}
