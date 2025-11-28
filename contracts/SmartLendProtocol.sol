State Variables
    address public owner;
    uint256 public constant COLLATERAL_RATIO = 150; 120% liquidation threshold
    uint256 public constant INTEREST_RATE = 5; Structs
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
    
    Pool variables
    uint256 public totalLiquidity;
    uint256 public totalBorrowed;
    
    Modifiers
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
    
    Constructor
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
        
        Transfer after state update (Checks-Effects-Interactions pattern)
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
        
        Create loan
        loans[msg.sender] = Loan({
            principal: loanAmount,
            collateral: msg.value,
            timestamp: block.timestamp,
            active: true,
            interestAccrued: 0
        });
        
        lastInterestUpdate[msg.sender] = block.timestamp;
        totalBorrowed += loanAmount;
        totalLiquidity += msg.value; Transfer loan amount to borrower
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
        
        Update state before transfers
        totalBorrowed -= principal;
        totalLiquidity -= collateralToReturn;
        delete loans[msg.sender];
        
        Return collateral to borrower
        payable(msg.sender).transfer(collateralToReturn);
        
        Check if collateral ratio falls below liquidation threshold (120%)
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
        
        Debt covered by collateral
        
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
// 
Contract End
// 
