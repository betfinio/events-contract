// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.25;

interface EventInterface {
    function getSides() external view returns (uint256[] memory);

    function getBetsCount() external view returns (uint256);

    function getBetsCountBySide(uint256 side) external view returns (uint256);

    function getSideBank(uint256 side) external view returns (uint256);

    function getBank() external view returns (uint256);

    function placeBet(address player, uint256 amount, bytes calldata data) external returns (address betAddress);
}
