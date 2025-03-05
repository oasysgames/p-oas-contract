# pOAS Token System

OASチェーン上で動作する担保付きポイントトークンシステムの実装です。

## 概要

このシステムは以下の3つの主要コントラクトで構成されています：

1. POAS (ERC20トークン)
2. ClaimSample (配布用コントラクト)
3. PaymentSample (支払い用コントラクト)

## コントラクトの詳細

### POAS Token

担保付きERC20トークンで、以下の特徴を持ちます：

- **基本情報**
  - 名前: pOAS
  - シンボル: pOAS
  - デシマル: 18

- **ロール管理**
  - ADMIN_ROLE: 担保の管理を行えます
  - MINTER_ROLE: 新規トークンを発行できます
  - PAYMENT_ROLE: トークンの支払い先として指定できます

- **主な機能**
  - mint: MINTERによる新規発行
  - bulkMint: 複数アドレスへの一括発行
  - depositCollateral: 担保の追加
  - withdrawCollateral: 担保の引き出し
  - transfer: PAYMENT_ROLEを持つアドレスへの送金時にOASに変換

- **担保管理**
  - 担保率 = コントラクト内のOAS残高 / pOASの総供給量
  - getCollateralRatio()で現在の担保率を確認可能
  - 担保率が1を下回ると支払いが失敗

### ClaimSample

pOASの配布用サンプルコントラクトです：

- 誰でも1回だけ100 pOASを受け取れます
- MINTER_ROLEが必要です
- 重複請求はできません

### PaymentSample

pOASでの支払いを受け付けるサンプルコントラクトです：

- PAYMENT_ROLEを持つ必要があります
- ユーザーからpOASを受け取り、自動的にOASに変換
- 管理者はコントラクトに蓄積されたOASを引き出し可能

## 利用の流れ

1. **トークンの取得**
   ```solidity
   // ClaimSampleを通じて取得
   claimSample.claim();
   
   // または直接MINTERから発行
   poas.mint(address, amount);
   ```

2. **支払いの実行**
   ```solidity
   // まずPaymentSampleコントラクトにapprove
   poas.approve(paymentSampleAddress, amount);
   
   // 支払いを実行
   paymentSample.pay(amount);
   ```

## セキュリティ上の注意点

1. **担保率の管理**
   - 担保率は常に1以上を維持することが推奨
   - オフチェーンで`getCollateralRatio()`を監視することを推奨

2. **ロールの管理**
   - ADMIN_ROLEは担保の管理を行うため、信頼できるアドレスのみに付与
   - MINTER_ROLEは新規発行が可能なため、適切に管理
   - PAYMENT_ROLEは支払い先として適切なコントラクトのみに付与

3. **支払い処理**
   - 支払い前に必ずapproveが必要
   - 担保不足時は支払いが失敗
   - 一般ユーザー間の転送は不可

## 開発・テスト

```bash
# 依存関係のインストール
npm install

# テストの実行
npm run test

# コントラクトのコンパイル
npm run compile

# デプロイ
npm run deploy
```

## 技術仕様

- Solidity ^0.8.20
- OpenZeppelin Contracts
  - ERC20
  - AccessControl
  - Ownable
  - ReentrancyGuard
- Hardhat開発環境
- TypeScriptによるテスト実装

## 制限事項

- 一般ユーザー間でのpOASの転送は不可
- 支払いはPAYMENT_ROLEを持つアドレスに対してのみ可能
- 担保不足時は支払い処理が失敗
- ClaimSampleは1アドレスにつき1回のみ請求可能
