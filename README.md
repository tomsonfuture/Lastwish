# 🏺 LastWish - Smart Will Execution Contract

> 💀 Auto-distribute inheritance when the heartbeat stops beating

## 📖 Overview

LastWish is a decentralized smart contract that enables automatic inheritance distribution based on a heartbeat mechanism. When a testator stops sending regular heartbeat signals, their will becomes executable and beneficiaries can claim their inheritance automatically.

## ✨ Features

- 💓 **Heartbeat Mechanism**: Testators must send regular heartbeat signals to prove they're alive
- 👥 **Multiple Beneficiaries**: Support for multiple beneficiaries with percentage-based distribution
- 🔒 **Secure Execution**: Wills can only be executed after the heartbeat interval expires
- 💰 **Flexible Funding**: Deposit and withdraw funds before execution
- 🎯 **Automatic Distribution**: Beneficiaries claim their inheritance directly from the contract

## 🚀 Quick Start

### Creating a Will

```clarity
;; Create a will with 1000 block heartbeat interval
(contract-call? .Lastwish create-will u1000)
```

### Adding Beneficiaries

```clarity
;; Add beneficiary with 50% inheritance
(contract-call? .Lastwish add-beneficiary u1 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u50)
```

### Depositing Funds

```clarity
;; Deposit 1000000 microSTX to the will
(contract-call? .Lastwish deposit-funds u1 u1000000)
```

### Sending Heartbeat

```clarity
;; Send heartbeat to prove you're alive
(contract-call? .Lastwish send-heartbeat u1)
```

### Executing Will

```clarity
;; Anyone can execute the will after heartbeat expires
(contract-call? .Lastwish execute-will u1)
```

### Claiming Inheritance

```clarity
;; Beneficiaries claim their inheritance
(contract-call? .Lastwish claim-inheritance u1)
```

## 🔍 Read-Only Functions

### Check Will Status
```clarity
(contract-call? .Lastwish get-will u1)
(contract-call? .Lastwish is-will-executable u1)
```

### Check Beneficiary Info
```clarity
(contract-call? .Lastwish get-beneficiary u1 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
(contract-call? .Lastwish get-inheritance-amount u1 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

## 📋 Contract Functions

| Function | Description | Access |
|----------|-------------|---------|
| `create-will` | Create a new will with heartbeat interval | Testator |
| `add-beneficiary` | Add beneficiary with inheritance percentage | Testator |
| `deposit-funds` | Deposit STX to the will | Testator |
| `send-heartbeat` | Send heartbeat signal | Testator |
| `withdraw-funds` | Withdraw funds before execution | Testator |
| `execute-will` | Execute will after heartbeat expires | Anyone |
| `claim-inheritance` | Claim inheritance after execution | Beneficiary |

## ⚠️ Important Notes

- 🕐 **Heartbeat Interval**: Set in blocks (1 block ≈ 10 minutes on Stacks)
- 💯 **Percentage Distribution**: Must add up beneficiaries manually
- 🔄 **One Will Per Address**: Each address can only create one will
- ⏰ **Execution Timing**: Will becomes executable only after heartbeat interval expires
- 💸 **Gas Costs**: Consider transaction fees for heartbeat maintenance

## 🛡️ Security Features

- ✅ Authorization checks for all testator functions
- ✅ Prevents double execution and double claiming
- ✅ Validates beneficiary percentages and amounts
- ✅ Secure fund transfers using STX native functions
- ✅ Heartbeat timing validation

## 🧪 Testing

Deploy the contract using Clarinet and test the complete flow:

1. Create will
2. Add beneficiaries
3. Deposit funds
4. Send heartbeats regularly
5. Stop heartbeats (simulate death)
6. Execute will after interval
7. Beneficiaries claim inheritance

## 📄 License

MIT License - Build the future of digital inheritance! 🚀
```

