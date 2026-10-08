// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Belchior Vault
/// @notice Holds BNB and allowed BEP-20 tokens. Each person withdraws only their own balance.
///         The owner can add a token to the list. The owner cannot withdraw deposits.
contract BelchiorVault {
    address public owner;
    mapping(address => bool) public allowed;
    mapping(address => mapping(address => uint256)) public balanceOf;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event TokenAllowed(address indexed token);
    event OwnerRenounced();

    error NotOwner();
    error TokenNotAllowed();
    error AmountZero();
    error Insufficient();
    error TransferFailed();
    error Reentered();

    uint256 private locked = 1;

    modifier nonReentrant() {
        if (locked != 1) revert Reentered();
        locked = 2;
        _;
        locked = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address[] memory tokens) {
        owner = msg.sender;
        allowed[address(0)] = true;
        emit TokenAllowed(address(0));
        uint256 n = tokens.length;
        for (uint256 i = 0; i < n; i++) {
            address token = tokens[i];
            if (token == address(0) || allowed[token]) continue;
            allowed[token] = true;
            emit TokenAllowed(token);
        }
    }

    function allowToken(address token) external onlyOwner {
        if (token == address(0) || allowed[token]) revert TokenNotAllowed();
        allowed[token] = true;
        emit TokenAllowed(token);
    }

    function renounceOwner() external onlyOwner {
        owner = address(0);
        emit OwnerRenounced();
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        if (token == address(0) || !allowed[token]) revert TokenNotAllowed();
        if (amount == 0) revert AmountZero();
        uint256 beforeBal = _balance(token);
        _transferFrom(token, msg.sender, address(this), amount);
        if (_balance(token) - beforeBal != amount) revert TransferFailed();
        balanceOf[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    function depositBNB() external payable nonReentrant {
        if (!allowed[address(0)]) revert TokenNotAllowed();
        if (msg.value == 0) revert AmountZero();
        balanceOf[msg.sender][address(0)] += msg.value;
        emit Deposit(msg.sender, address(0), msg.value);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert AmountZero();
        uint256 bal = balanceOf[msg.sender][token];
        if (bal < amount) revert Insufficient();
        balanceOf[msg.sender][token] = bal - amount;
        if (token == address(0)) {
            (bool ok, ) = msg.sender.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            _transfer(token, msg.sender, amount);
        }
        emit Withdraw(msg.sender, token, amount);
    }

    receive() external payable {
        revert();
    }

    function _balance(address token) private view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(hex"70a08231", address(this))
        );
        if (!ok || data.length < 32) revert TransferFailed();
        return abi.decode(data, (uint256));
    }

    function _transferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(hex"23b872dd", from, to, amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _transfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(hex"a9059cbb", to, amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
