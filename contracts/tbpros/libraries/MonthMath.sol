// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice Strict next UTC Gregorian month, using a March-based 400-year cycle.
/// No epoch/holder history scan. Pure calendar implementation, independently tested against Python datetime.
library MonthMath {
    function nextMonth(uint64 timestamp) internal pure returns (uint64) {
        // March 1 year 0 to Unix epoch = 719468 days. Each 400 years has 146097 days.
        uint256 z = uint256(timestamp) / 1 days + 719468;
        uint256 era = z / 146097;
        uint256 dayOfEra = z % 146097;
        uint256 yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365;
        uint256 year = yearOfEra + era * 400;
        uint256 dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100);
        uint256 marchMonth = (5 * dayOfYear + 2) / 153;
        uint256 month = marchMonth < 10 ? marchMonth + 3 : marchMonth - 9;
        if (month <= 2) ++year;
        if (month == 12) {
            ++year;
            month = 1;
        } else {
            ++month;
        }
        // Convert the first of the next month back to Unix days, with no day-of-month term.
        uint256 marchYear = year - (month <= 2 ? 1 : 0);
        uint256 y = marchYear % 400;
        uint256 m = month > 2 ? month - 3 : month + 9;
        uint256 days_ = (marchYear / 400) * 146097 + 365 * y + y / 4 - y / 100 + (153 * m + 2) / 5 - 719468;
        return SafeCast.toUint64(days_ * 1 days);
    }
}
