Project Summary

This repository implements Autopilot Wallet, a smart wallet deployed on Base that automatically manages idle capital.
The wallet behaves like a normal self-custodial wallet (send/receive/pay), but internally it:

keeps a checking balance in USDC

routes any excess into yield strategies

withdraws from yield automatically when a user pays

optionally sweeps dust tokens into USDC and compounds them into yield

All automation happens inside the wallet using ERC-4337 + ERC-7579, not through off-chain custody, vaults, or bots.

The core interaction is a single gasless userOperation that can internally:

withdraw → pay → re-deposit

This is the expected and intended behavior.

Core Architecture

The system consists of five components:

Smart Account (4337)

ZeroDev Kernel v3

AutoYieldModule (ERC-7579)

Contains yield logic and configuration

YieldAdapter (ERC-4626 interface)

Strategy wrapper for vaults

Vault

Either a real ERC-4626 vault on Base or a mock vault with the same interface

Base Paymaster

Sponsors gas for allowed operations

Provider decisions

These are final unless explicitly changed by the repo maintainer:

Smart account: ZeroDev Kernel v3

Module standard: ERC-7579

Network: Base (Base Sepolia during development)

Bundler: Base bundler endpoint

Gas sponsorship: Base Paymaster

Primary token: USDC (native)

Yield: ERC-4626 vault (Aerodrome/Beefy) or Mock vault if necessary

Dust swaps: Aerodrome router (fallback Uniswap v3 Base)

Frontend chain interaction: OnchainKit + viem

Expected Contract Behavior

All automation flows through:

executeWithAutoYield(token, to, amount, data)


Internal logic must follow this exact sequence:

Check if spendable balance >= amount + threshold

If not, withdraw the deficit from yield via the adapter

Execute the user’s transfer/purchase call

After execution, if balance exceeds threshold, deposit surplus into yield

Optionally sweep dust → consolidate → deposit

All steps happen within the same userOp.

There should never be a design that:

relies on off-chain bots to unstake before spending

requires the user to manually move funds in/out of yield

triggers a second transaction after payment

Scope Boundaries

The following are in scope:

configurable check-balance threshold per token

per-token strategy enable/disable

dust consolidation into USDC

multicall sequencing inside 4337

gasless UX via paymaster

The following are not in scope without explicit approval:

switching to Safe/Argent/Biconomy stack

using non-Base networks

custodial vault pooling

leveraged yield strategies

proxy upgrade patterns unless requested

moving logic off-chain when it should be in the module

Rules for AI Contributions

These rules apply to any AI code generation inside this repo:

If anything is unclear, always ask for clarification before generating code.

Never invent architecture, folders, or providers.
Stay within the decisions documented above.

Never rename or replace the core constructs:

Smart account

AutoYieldModule

YieldAdapter

Never create new major dependencies without explicit approval.

Do not redesign the repo based on personal preference.

Follow minimal assumptions.
If something could be done in multiple ways, ask the maintainer which direction to take.

Do not generate placeholder abstractions that are not planned in the scope.

If an operation appears complex, produce a step-by-step plan before producing code.

Preferred Interaction Model for Claude

Whenever generating code or making changes, Claude should:

state what file(s) it plans to modify

request confirmation before writing

describe architectural decisions before implementing them

ask questions when ambiguity is present

avoid “creative” or speculative changes

If the maintainer asks Claude to “just write the code”, Claude may execute without reconfirming — otherwise assume confirmation is required.

Definition of Completion

The project is considered correct when the wallet can:

receive USDC

auto-allocate surplus to yield

execute executeWithAutoYield which:

withdraws from yield if needed

performs user transfer

re-allocates surplus into yield

perform the above in a single userOperation with gas sponsored

sweep dust balances into USDC and compound them (if configured)

No additional functionality is required unless requested.
