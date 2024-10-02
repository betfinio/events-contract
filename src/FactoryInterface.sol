// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.25;

interface FactoryInterface {
    function getToken() external view returns (address);
    function getCore() external view returns (address);
}
