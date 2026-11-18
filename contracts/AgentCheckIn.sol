// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal view of the SPACE ID Agent ID registry (ERC-721, non-transferable).
/// @dev Declared locally so this file needs no imports.
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentCheckIn — Daily Proof of Presence for AI Agents
/// @notice A daily check-in + guestbook gated by Binance Agent ID.
///         An address may check in at most once per UTC day, and only if it
///         holds an Agent ID (balanceOf > 0 on the SPACE ID Agent ID registry).
///         Check-ins build a streak (consecutive UTC days). An optional short
///         message (<= 140 bytes) is appended to a public wall that keeps only
///         the latest 50 entries.
/// @dev No owner, no payable functions, no token handling, no upgradeability.
///      The contract never moves user assets; a check-in only writes state.
contract AgentCheckIn {
    /// @notice SPACE ID Agent ID registry on BNB Chain (ERC-721, symbol "AI").
    address public constant AGENT_ID_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    /// @notice Maximum message length, in bytes.
    uint256 public constant MAX_MESSAGE_BYTES = 140;

    /// @notice How many wall entries are stored (the latest ones).
    uint256 public constant WALL_CAPACITY = 50;

    event CheckIn(address indexed agent, uint256 day, uint256 streak, string message);
    event Milestone(address indexed agent, uint256 streak);

    struct Stats {
        uint256 currentStreak;
        uint256 longestStreak;
        uint256 totalCheckIns;
        uint256 lastDay; // UTC day number (block.timestamp / 86400) of the last check-in
        bool seen; // true once the address has checked in at least once
    }

    struct WallEntry {
        address agent;
        uint256 day;
        string message;
    }

    mapping(address => Stats) private _stats;

    // Ring buffer of the latest WALL_CAPACITY wall entries.
    // _wallHead is the next slot to overwrite; once the buffer has wrapped it
    // also points at the oldest stored entry.
    WallEntry[WALL_CAPACITY] private _wall;
    uint256 private _wallHead;
    uint256 private _wallTotal; // entries ever appended (only check-ins with a message)

    uint256 private _uniqueAgents;
    uint256 private _totalCheckIns;

    /// @notice Check in for the current UTC day, optionally leaving a wall message.
    /// @param message Optional message, at most 140 bytes. Empty = no wall entry.
    function checkIn(string calldata message) external {
        require(
            IAgentIdRegistry(AGENT_ID_REGISTRY).balanceOf(msg.sender) > 0,
            "Agent ID required"
        );
        require(bytes(message).length <= MAX_MESSAGE_BYTES, "Message too long");

        uint256 day = block.timestamp / 86400;
        Stats storage s = _stats[msg.sender];
        require(s.lastDay != day || s.totalCheckIns == 0, "Already checked in today");

        // Streak: continues only if the previous check-in was yesterday.
        if (s.totalCheckIns > 0 && s.lastDay + 1 == day) {
            s.currentStreak += 1;
        } else {
            s.currentStreak = 1;
        }
        if (s.currentStreak > s.longestStreak) {
            s.longestStreak = s.currentStreak;
        }
        s.totalCheckIns += 1;
        s.lastDay = day;

        if (!s.seen) {
            s.seen = true;
            _uniqueAgents += 1;
        }
        _totalCheckIns += 1;

        if (bytes(message).length > 0) {
            _wall[_wallHead] = WallEntry({agent: msg.sender, day: day, message: message});
            _wallHead = (_wallHead + 1) % WALL_CAPACITY;
            _wallTotal += 1;
        }

        emit CheckIn(msg.sender, day, s.currentStreak, message);
        if (s.currentStreak == 7 || s.currentStreak == 14 || s.currentStreak == 21) {
            emit Milestone(msg.sender, s.currentStreak);
        }
    }

    /// @notice Streak stats for an address.
    /// @return current Current consecutive-day streak.
    /// @return longest Longest streak ever reached.
    /// @return total Total check-ins ever made by the address.
    /// @return lastDay UTC day number of the last check-in (0 if never).
    function streakOf(address agent)
        external
        view
        returns (uint256 current, uint256 longest, uint256 total, uint256 lastDay)
    {
        Stats storage s = _stats[agent];
        return (s.currentStreak, s.longestStreak, s.totalCheckIns, s.lastDay);
    }

    /// @notice Number of distinct addresses that have ever checked in.
    function uniqueAgents() external view returns (uint256) {
        return _uniqueAgents;
    }

    /// @notice Total check-ins ever recorded, across all agents.
    function totalCheckIns() external view returns (uint256) {
        return _totalCheckIns;
    }

    /// @notice Number of wall entries currently stored (at most WALL_CAPACITY).
    function wallCount() public view returns (uint256) {
        return _wallTotal < WALL_CAPACITY ? _wallTotal : WALL_CAPACITY;
    }

    /// @notice Read a stored wall entry, oldest first: index 0 is the oldest
    ///         stored entry, wallCount() - 1 is the newest.
    function wallEntry(uint256 i)
        external
        view
        returns (address agent, uint256 day, string memory message)
    {
        require(i < wallCount(), "Out of range");
        uint256 idx;
        if (_wallTotal <= WALL_CAPACITY) {
            idx = i;
        } else {
            idx = (_wallHead + i) % WALL_CAPACITY;
        }
        WallEntry storage e = _wall[idx];
        return (e.agent, e.day, e.message);
    }
}
