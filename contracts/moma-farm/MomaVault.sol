// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./interfaces/IMomaFarm.sol";

// MomaVault
contract MomaVault is AccessControlEnumerable {
    using SafeERC20 for IERC20;

    address public moma;

    bytes32 public constant FARM_ROLE = keccak256("FARM_ROLE");

    modifier onlyFarm() {
        require(hasRole(FARM_ROLE, _msgSender()), "MomaVault: Not Farm");
        _;
    }

    constructor(address _moma, address _farm) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(FARM_ROLE, _farm);

        moma = _moma;
    }

    function depositFunds(uint256 _amount) external {
        IERC20(moma).safeTransferFrom(msg.sender, address(this), _amount);
    }

    // Safe moma transfer function, just in case if rounding error causes pool to not have enough MOMAs.
    function safeMomaTransfer(address _to, uint256 _amount) external onlyFarm {
        uint256 momaBal = IERC20(moma).balanceOf(address(this));
        if (_amount > momaBal) {
            IERC20(moma).safeTransfer(_to, momaBal);
        } else {
            IERC20(moma).safeTransfer(_to, _amount);
        }
    }

    function rescueFunds(
        address tokenToRescue,
        address to,
        uint256 amount
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "MomaVault: Not Admin");
        IERC20(tokenToRescue).safeTransfer(to, amount);
    }
}
