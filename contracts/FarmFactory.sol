// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract FarmFactory is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _farms;
    EnumerableSet.AddressSet private _farmGenerators;

    mapping(address => EnumerableSet.AddressSet) private _userFarms;

    function adminAllowFarmGenerator(address _address, bool _allow) public onlyOwner {
        if (_allow) {
            _farmGenerators.add(_address);
        } else {
            _farmGenerators.remove(_address);
        }
    }

    /**
     * @notice called by a registered FarmGenerator upon Farm creation
     */
    function addFarm(address _farmAddress) public {
        require(_farmGenerators.contains(msg.sender), "FORBIDDEN");
        _farms.add(_farmAddress);
    }

    /**
     * @notice Number of allowed _FarmGenerators
     */
    function farmGeneratorsLength() external view returns (uint256) {
        return _farmGenerators.length();
    }

    /**
     * @notice Gets the address of a registered FarmGenerator at specifiex index
     */
    function farmGeneratorAtIndex(uint256 _index) external view returns (address) {
        return _farmGenerators.at(_index);
    }

    /**
     * @notice The length of all farms on the platform
     */
    function farmsLength() external view returns (uint256) {
        return _farms.length();
    }

    /**
     * @notice gets a farm at a specific index. Although using Enumerable Set, since farms are only added and not removed this will never change
     * @return the address of the Farm contract at index
     */
    function farmAtIndex(uint256 _index) external view returns (address) {
        return _farms.at(_index);
    }

    /**
     * @notice called by a Farm contract when lp token balance changes from 0 to > 0 to allow tracking all farms a user is active in
     */
    function userEnteredFarm(address _user) public {
        // msg.sender = farm contract
        require(_farms.contains(msg.sender), "FORBIDDEN");
        EnumerableSet.AddressSet storage set = _userFarms[_user];
        set.add(msg.sender);
    }

    /**
     * @notice called by a Farm contract when all LP tokens have been withdrawn, removing the farm from the users active farm list
     */
    function userLeftFarm(address _user) public {
        // msg.sender = farm contract
        require(_farms.contains(msg.sender), "FORBIDDEN");
        EnumerableSet.AddressSet storage set = _userFarms[_user];
        set.remove(msg.sender);
    }

    /**
     * @notice returns the number of farms the user is active in
     */
    function userFarmsLength(address _user) external view returns (uint256) {
        EnumerableSet.AddressSet storage set = _userFarms[_user];
        return set.length();
    }

    /**
     * @notice called by a Farm contract when all LP tokens have been withdrawn, removing the farm from the users active farm list
     * @return the address of the Farm contract the user is farming
     */
    function userFarmAtIndex(address _user, uint256 _index) external view returns (address) {
        EnumerableSet.AddressSet storage set = _userFarms[_user];
        return set.at(_index);
    }
}
