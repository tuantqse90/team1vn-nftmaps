#!/usr/bin/env bash
# Deploy MapNFT + MapAccountFactory + RunNFT lên Avalanche Fuji rồi tự điền địa chỉ vào ios/NFTMaps/Config.swift.
#
#   scripts/deploy-fuji.sh                 # dùng keystore "nftmaps-deployer" trong ~/.foundry/keystores
#   ACCOUNT=ten-khac scripts/deploy-fuji.sh
#   VERIFY=1 scripts/deploy-fuji.sh        # verify source trên Snowtrace (Routescan) luôn
#
# Tài khoản deploy sẽ là owner = moderator của MapNFT (ẩn bé khỏi bản đồ bằng setHidden).
#
# Mật khẩu keystore: nếu có trong macOS Keychain (service "foundry-keystore", account = tên keystore) thì
# script tự lấy, không thì forge hỏi. Biến cho test local: RPC (mặc định "fuji"), PRIVATE_KEY (thay keystore), CONFIG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RPC="${RPC:-fuji}"
CONFIG="${CONFIG:-$ROOT/ios/NFTMaps/Config.swift}"

if [[ -n "${PRIVATE_KEY:-}" ]]; then
  SIGNER=(--private-key "$PRIVATE_KEY")
else
  ACCOUNT="${ACCOUNT:-nftmaps-deployer}"
  SIGNER=(--account "$ACCOUNT")
  if PASSWORD="$(security find-generic-password -s foundry-keystore -a "$ACCOUNT" -w 2>/dev/null)"; then
    PASSWORD_FILE="$(mktemp)"
    chmod 600 "$PASSWORD_FILE"
    trap 'rm -f "$PASSWORD_FILE"' EXIT
    printf '%s' "$PASSWORD" >"$PASSWORD_FILE"
    unset PASSWORD
    SIGNER+=(--password-file "$PASSWORD_FILE")
  fi
fi
EXTRA=()
[[ "${VERIFY:-0}" == "1" ]] && EXTRA+=(--verify)

cd "$ROOT/contracts"
forge test -q
OUTPUT="$(forge script script/Deploy.s.sol --rpc-url "$RPC" "${SIGNER[@]}" --broadcast ${EXTRA[@]+"${EXTRA[@]}"} 2>&1 | tee /dev/stderr)"

NFT="$(grep "MapNFT deployed at:" <<<"$OUTPUT" | awk '{print $NF}')"
FACTORY="$(grep "MapAccountFactory deployed at:" <<<"$OUTPUT" | awk '{print $NF}')"
RUN_NFT="$(grep "RunNFT deployed at:" <<<"$OUTPUT" | awk '{print $NF}')"
ADDRESS_RE='^0x[0-9a-fA-F]{40}$'
if [[ ! "$NFT" =~ $ADDRESS_RE || ! "$FACTORY" =~ $ADDRESS_RE || ! "$RUN_NFT" =~ $ADDRESS_RE ]]; then
  echo "❌ Không đọc được địa chỉ contract từ output của forge." >&2
  exit 1
fi

sed -i '' -E "s/(static let mapNFT = )\"[^\"]*\"/\1\"$NFT\"/" "$CONFIG"
sed -i '' -E "s/(static let accountFactory = )\"[^\"]*\"/\1\"$FACTORY\"/" "$CONFIG"
sed -i '' -E "s/(static let runNFT = )\"[^\"]*\"/\1\"$RUN_NFT\"/" "$CONFIG"

echo
echo "✅ MapNFT            $NFT"
echo "✅ MapAccountFactory $FACTORY"
echo "✅ RunNFT            $RUN_NFT"
echo "   Đã ghi vào $CONFIG"
if grep -q 'static let pimlicoAPIKey = ""' "$CONFIG"; then
  echo "👉 Còn thiếu pimlicoAPIKey trong Config.swift (https://dashboard.pimlico.io)."
fi
