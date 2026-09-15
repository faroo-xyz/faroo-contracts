// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// TEST-ONLY countermodels. No production deployment or full Vault semantics.
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RegressionAsset is ERC20 {
    constructor() ERC20("Regression asset", "TEST") {}

    function mint(address to, uint256 a) external {
        _mint(to, a);
    }
}

contract MintModel {
    RegressionAsset public immutable token;
    bool public immutable gated;
    uint256 public R;
    uint256 public S;
    mapping(address => uint256) public shares;
    uint256 public lastLossBpsCeil;
    uint256 public constant LOSS_BPS = 1; // Experimental, NOT product-approved.

    error UnfairMint();

    constructor(uint256 r, uint256 s, bool g, RegressionAsset t) {
        R = r;
        S = s;
        gated = g;
        token = t;
        shares[msg.sender] = s;
        // Test fixture: represents already funded seed/yield, not a production mint authority.
        t.mint(address(this), r);
    }

    function subscribe(uint128 a) external returns (uint256 q) {
        require(a > 0 && R > 0 && S > 0);
        q = Math.mulDiv(a, S, R);
        uint256 remainder = mulmod(a, S, R);
        uint256 loss = Math.mulDiv(remainder, 10_000, uint256(a) * S, Math.Rounding.Ceil);
        if (gated && (q == 0 || loss > LOSS_BPS)) revert UnfairMint();
        require(q > 0);
        // Gate precedes even the first asset transfer in this exact-output model.
        token.transferFrom(msg.sender, address(this), a);
        R += a;
        S += q;
        shares[msg.sender] += q;
        lastLossBpsCeil = loss;
    }

    function fastBurn(uint256 q) external returns (uint256 paid) {
        require(q <= S && q > 0 && q <= shares[msg.sender]);
        paid = Math.mulDiv(q, R, S);
        R -= paid;
        S -= q;
        shares[msg.sender] -= q;
        token.transfer(msg.sender, paid);
    }
}

contract ExitModel {
    bool public riskPaused;
    bool public requestsPaused;
    address public immutable guardian;
    mapping(address => uint256) public balances;
    mapping(address => mapping(uint256 => uint256)) public positions;
    mapping(uint256 => uint256) public epochShares;
    uint256 public escrow;
    uint256 public helpersCalled;

    constructor(address g) {
        guardian = g;
    }

    function seed(address a, uint256 q) external {
        balances[a] += q;
    }

    function pauseBoth() external {
        require(msg.sender == guardian);
        riskPaused = true;
        requestsPaused = true;
    }

    function ordinaryRequest(uint256 q, uint256 epoch) external {
        require(!requestsPaused);
        _request(q, epoch);
    }

    function safeRequest(uint256 q, uint256 epoch) external {
        _request(q, epoch);
    }

    function _request(uint256 q, uint256 epoch) internal {
        // Calendar injected by the test: production MUST derive, never trust caller.
        require(epoch > block.timestamp && q > 0 && q <= balances[msg.sender]);
        balances[msg.sender] -= q;
        positions[msg.sender][epoch] += q;
        epochShares[epoch] += q;
        escrow += q;
        helpersCalled++;
    }
}

contract YieldModel {
    bool public immutable checkpointed;
    uint256 public R = 1_000_000 ether;
    uint256 public S = 1_000_000 ether;
    uint256 public U = 1_000_000 ether; // test uses a common decimal scale
    uint256 public H = 1_000_000 ether; // already funded; excluded from share price
    uint256 public last;
    uint256 public end;
    uint256 public remainder;
    mapping(address => uint256) public shares;

    constructor(bool fixedVersion, address incumbent) {
        checkpointed = fixedVersion;
        shares[incumbent] = S;
        last = block.timestamp;
        end = last + 30 days;
    }

    function checkpoint() public {
        uint256 until = Math.min(block.timestamp, end);
        uint256 numerator = U * (until - last) + remainder;
        uint256 gain = numerator / (20 * 365 days);
        remainder = numerator % (20 * 365 days);
        require(gain <= H);
        H -= gain;
        R += gain;
        last = until;
    }

    function subscribe(uint256 a) external returns (uint256 q) {
        if (checkpointed) checkpoint();
        q = Math.mulDiv(a, S, R);
        shares[msg.sender] += q;
        S += q;
        R += a;
        U += a;
    }

    function nav() external {
        if (checkpointed) {
            checkpoint();
        } else {
            uint256 gain = U / (20 * 365);
            H -= gain;
            R += gain;
        }
    }

    function transfer(address to, uint256 q) external {
        // Ordinary bearer transfer does not change U/S or checkpoint.
        shares[msg.sender] -= q;
        shares[to] += q;
    }

    function fastAll() external returns (uint256 paid) {
        if (checkpointed) checkpoint();
        uint256 q = shares[msg.sender];
        paid = Math.mulDiv(q, R, S);
        U -= Math.mulDiv(q, U, S);
        S -= q;
        R -= paid;
        shares[msg.sender] = 0;
        // Zero fee deliberately: yield attribution must not rely on a penalty.
    }
}

contract InventoryModel {
    uint256 public immutable capacity;
    uint256 public immutable refillPerSecond;
    uint256 public tokens;
    uint256 public last;
    uint256 public spent;
    uint256 public outstanding;
    uint256 public reserve = 10_000_000 ether;
    bool public immutable bounded;
    bool public immutable pegGuard;

    constructor(bool bounded_, bool peg_) {
        bounded = bounded_;
        pegGuard = peg_;
        capacity = 100_000 ether;
        refillPerSecond = 1 ether;
        tokens = capacity;
        last = block.timestamp;
    }

    function subscribe(uint256 usdcValue18, uint256 prosUsd18, uint256 usdcUsd18) external returns (uint256 p) {
        require(prosUsd18 > 0);
        if (pegGuard) require(usdcUsd18 >= 0.99 ether && usdcUsd18 <= 1.01 ether, "DEPEG");
        p = Math.mulDiv(usdcValue18, 1 ether, prosUsd18); // face-value branch
        if (bounded) {
            tokens = Math.min(capacity, tokens + (block.timestamp - last) * refillPerSecond);
            last = block.timestamp;
            require(p <= tokens, "FLOW");
            tokens -= p;
        }
        require(p <= reserve);
        reserve -= p;
        spent += p;
        outstanding += p;
    }

    function exitAll() external {
        outstanding = 0;
    } // never refills risk tokens
}

contract LossSnapshotModel {
    uint256 public R;
    uint256 public P;
    uint256 public F;
    uint256 public L;
    uint256 public immutable initialP;
    uint256 public payoutBudget;
    bool public reconciled;
    mapping(address => uint256) public entitlement;
    mapping(address => bool) public claimed;

    constructor(uint256 r, uint256 p, uint256 f, uint256 l, address a, address b) {
        R = r;
        P = p;
        F = f;
        L = l;
        initialP = p;
        entitlement[a] = p / 2;
        entitlement[b] = p - p / 2;
    }

    function legacyClaim() external view {
        require(L >= R + P + F, "GLOBAL_DEFICIT");
    }

    function reconcileSenior() public {
        if (reconciled) return;
        uint256 loss = R + P + F > L ? R + P + F - L : 0;
        uint256 cut = Math.min(F, loss);
        F -= cut;
        loss -= cut;
        cut = Math.min(R, loss);
        R -= cut;
        loss -= cut;
        cut = Math.min(P, loss);
        P -= cut;
        payoutBudget = P;
        reconciled = true;
    }

    function claim() external returns (uint256 a) {
        reconcileSenior();
        require(!claimed[msg.sender]);
        claimed[msg.sender] = true;
        a = Math.mulDiv(entitlement[msg.sender], payoutBudget, initialP);
        P -= a;
        L -= a;
        // Single fixed loss snapshot only. Multi-loss/new-epoch index NOT implemented.
    }
}
