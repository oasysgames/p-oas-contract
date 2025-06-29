# pOAS
pOAS is a point OAS designed for use within the Oasys ecosystem. It is implemented as an ERC-20 token and is intended to maintain a 1:1 value parity with native OAS (i.e., 1 OAS = 1 pOAS).

We designed pOAS to function as a point system. Holders can use pOAS as a payment method for pre-registered contracts. When pOAS is transferred, it is burned, and the recipient receives the equivalent amount in native OAS. To prevent unintended payments or exchanges, only whitelisted recipient addresses can receive pOAS.

Although pOAS holds the same value as OAS, it is not fully collateralized. The collateral ratio is below 100%, and the value is maintained based on trust in the issuer. The issuer must carefully manage the collateral balance to ensure that there is no shortage of native OAS.


## Specifications
- ERC-20 Token
  - Name: oPAS
  - Symbol: pOAS
  - Decimals: 18
  - Transfer:
    - Only whitelisted addresses (with RECIPIENT_ROLE) can receive pOAS.
    - Upon transfer, pOAS is burned and the recipient receives the equivalent amount of native OAS.
  - Mint: Only addresses with the OPERATOR_ROLE can mint pOAS.
  - Burn: Self-burnable by the holder
- Roles
  - ADMIN_ROLE:
    - Assigned to the admin account.
    - Can grant or revoke other roles.
  - OPERATOR_ROLE:
    - Assigned to operator accounts responsible for daily pOAS operations.
    - Can perform the following actions:
      - Mint pOAS
      - Add or withdraw collateralized OAS
      - Manage pOAS recipients by granting or revoking RECIPIENT_ROLE
  - RECIPIENT_ROLE:
    - Assigned to addresses allowed to receive pOAS.
    - Only holders of this role can receive pOAS.
- Supports deposit/withdrawal of collateral OAS by operators
- Includes a read-only function to retrieve the list of recipient addresses in JSON format
- Uses the proxy pattern to support future upgrades

## Sample Contracts
- [PaymentSample](./src/samples/PaymentSample.sol): A contract that accepts pOAS as a payment method.
- [ClaimSample](./src/samples/ClaimSample.sol): A contract for distributing pOAS to users as part of promotional campaigns or in-game events.

## Deploy
You can deploy the pOAS contract easily using the pre-configured deployment script.

1. Set Up Environment Variables
First, copy the example environment file and adjust it to your own setup:
```sh
cp .envrc.example .envrc
```
This script deploys pOAS as an upgradeable proxy, so a proxy admin address is required. In most cases, the proxy admin and the pOAS admin are the same address. You can simply specify the same address in your environment variables. Check the comments in `.envrc.example` for more detailed guidance on each variable.

2. Configure Explorer for Contract Verification
To enable contract verification on your block explorer, add the following to `foundry.toml`:
```toml
[etherscan]
yourchain = { key = "${ETHERSCAN_API_KEY}", chain = "chainID", url = "https://explorer-domain/api" }
```

3. Deploy & Verify
Once your environment is configured, run the deployment script:
```sh
npm run deploy
```

### Sample Deployment Scripts

Deployment scripts for the example contracts live in the `script/` directory.
When running these scripts make sure the following environment variables are set:

- `USE_PROXY_ADMIN` – `true` to deploy a `ProxyAdmin` contract, `false` to have the proxy owned directly by `PROXY_OWNER`.
- `PROXY_OWNER` – Address that becomes the admin of the proxy (or owner of the `ProxyAdmin`).
- `POAS_ADDRESS` – Address of the deployed POAS contract used by the samples.
- `EX_CONTRACT` – (PaymentPracticalSample only) External contract address called after a payment.
- `PAYMENT_PRICE` – (PaymentPracticalSample only) Initial payment price in wei.

