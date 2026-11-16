# NFT Maps

App iOS (Swift) trên **Avalanche Fuji** (chain ID 43113): gặp chó hay mèo ngoài đường thì mở camera "đi bắt" như chơi game. Model trên máy khoanh vòng ngắm quanh bé, bạn vuốt ném bóng vào bé, trúng thì bắt được, và ảnh bé được mint thành NFT gắn đúng toạ độ nơi bạn đứng.
Người dùng chỉ cần đăng nhập bằng username và mật khẩu. App không hiện popup ký, và người dùng không cần có AVAX.

## Tính năng

- **Đăng nhập không cần ví ngoài:** username + mật khẩu sinh ra key. Smart account ERC-4337 được tạo sẵn, paymaster trả gas.
- **Màn bắt kiểu game:** camera trực tiếp, nhận diện chó/mèo ngay trên máy, vuốt ném bóng, bóng lắc 3 lần, pháo hoa, thẻ "Bắt được rồi!".
- **NFT hoàn toàn on-chain:** ảnh JPEG, tên, loài, độ tin cậy, toạ độ. `tokenURI` được dựng ngay trong contract.
- **Bản đồ:** ghim là ảnh thật của từng bé, viền tím cho bé của bạn, cam cho bé của người khác. Mint xong bản đồ bay tới bé mới.
- **Bộ sưu tập:** hồ sơ và thống kê mèo/chó, lưới ảnh "Của tôi" và "Mọi người".
- **Màn chi tiết:** bản đồ nhỏ, nút chỉ đường (Apple Maps), chia sẻ ảnh, link Snowtrace.
- **Chạy bộ:** đặt mục tiêu theo mét hoặc bước, 3 vòng gợi ý quanh chỗ đứng. Màn chạy đếm mét (GPS, thiếu GPS thì lấy pedometer), bước, nhịp, và đọc mốc mỗi km bằng giọng Việt. Thử thách giữa vòng: **Bứt tốc** (200 m/60 s) và **Giữ nhịp** (500 m).
- **Game:** XP, cấp, xu, vé x2 XP, combo gặp bé, 4 nhiệm vụ ngày, rương, chuỗi ngày, 3 huy chương. Độ hiếm của bé (Phổ thông → Huyền thoại) tính theo mật độ bé quanh chỗ mint. Gặp lại bé quen (so feature-print Vision) thì +XP thay vì mint trùng.
- **Run NFT:** mint vòng chạy thành NFT on-chain, gồm hình tuyến, quãng đường, bước, thời gian. Có bảng xếp hạng theo khu ~1 km, đọc từ chain.
- **Trạm:** quán đối tác (check-in trong 60 m) và điểm cho ăn (góp xu). ⚠️ Danh sách trạm trong `Core/Stations.swift` hiện là **dữ liệu mẫu**.
- **Bạn bè:** theo dõi theo địa chỉ ví, xem bảng tin bé và vòng chạy họ mint (đọc từ chain, không cần server).
- **Bé nhà bạn? / Bé cần giúp:** gửi yêu cầu ẩn bé (moderator gọi `setHidden`) hoặc báo bé cần cứu qua share sheet. Vị trí chính xác chỉ nằm trong tin nhắn bạn gửi đi.
- **Offline:** bản đồ dùng snapshot chain đã cache. Bé chụp lúc mất mạng được xếp hàng "Bé chờ mint" để gửi sau.

## Riêng tư vị trí

- Toạ độ bé được kéo về **tâm ô lưới 100 m** trước khi mint (bật mặc định, tắt được ở Cài đặt). Đã lên chain thì không xoá được.
- Run NFT **không lưu toạ độ thật**. Contract chỉ nhận hình tuyến đã chuẩn hoá về lưới 256×256 (bỏ 200 m đầu và cuối) cùng ô khu ~1 km (lat/lng × 100). Vòng dưới 500 m không mint được.
- `setHidden` chỉ bỏ ghim khỏi app. Toạ độ (đã làm mờ) vẫn nằm trên chain.

```
contracts/   Solidity + Foundry
  MapNFT.sol              ERC-721: toạ độ, loài, độ tin cậy, tên, ảnh JPEG on-chain; tokenURI dựng ngay trong contract; owner ẩn bé (setHidden)
  RunNFT.sol              ERC-721 vòng chạy: quãng đường, bước, thời gian, ô khu ~1 km, hình tuyến; tokenURI là SVG on-chain
  SSTORE2.sol             lưu ảnh làm bytecode của contract con (rẻ hơn SSTORE ~3 lần)
  MapAccount.sol          smart account ERC-4337 (OpenZeppelin Account + SignerECDSA), một chủ
  MapAccountFactory.sol   tạo MapAccount (clone) tại địa chỉ xác định trước theo owner
ios/         SwiftUI + MapKit, project sinh bằng XcodeGen
  NFTMaps/Core/           keccak, ABI, RPC, ký secp256k1, UserOperation, Pimlico, nhận diện chó/mèo, làm mờ vị trí, NullMaps (không phụ thuộc UI)
  NFTMaps/Core/Game/      luật game (XP, cấp, độ hiếm), thử thách, GameStore (lưu JSON trên máy), RunTracker (GPS + pedometer)
  NFTMaps/Session/        Keychain + phiên đăng nhập
  NFTMaps/Views/          đăng nhập, tab bar, bản đồ, nhiệm vụ, bộ sưu tập, hồ sơ, bạn bè, cài đặt, trạm, sheet mint
  NFTMaps/Views/Run/      chuẩn bị chạy, màn chạy, tổng kết + mint vòng chạy
  NFTMaps/Views/Catch/    màn "bắt": camera + nhận diện trực tiếp, ném bóng, hiệu ứng
  NFTMapsTests/           unit test (vector so với cast, Python và EntryPoint thật trên Fuji; luật game, làm mờ vị trí)
  NFTMapsUITests/         tour chụp màn hình các màn chính
scripts/deploy-fuji.sh    deploy contracts và tự điền địa chỉ vào Config.swift
```

## Cài đặt

### 1. Deploy contracts

Đã deploy và verify trên Fuji (`Config.swift` đã có sẵn địa chỉ):

| Contract | Địa chỉ |
|---|---|
| MapNFT | [`0x350cb01b077DDD71D81Ecf94E13f1E94C8b048A0`](https://testnet.snowtrace.io/address/0x350cb01b077DDD71D81Ecf94E13f1E94C8b048A0) |
| MapAccountFactory | [`0xf5dBBA586FACD6e70b6199E3a5e4f27d57aD3743`](https://testnet.snowtrace.io/address/0xf5dBBA586FACD6e70b6199E3a5e4f27d57aD3743) |
| RunNFT | [`0xfd2786B894a387149Ab132fDdF7Fff483a5FE1de`](https://testnet.snowtrace.io/address/0xfd2786B894a387149Ab132fDdF7Fff483a5FE1de) |

Ví deploy là owner (moderator) của MapNFT. Deploy lại:

Cần AVAX test trong ví deploy: https://core.app/tools/testnet-faucet

```bash
cd contracts && git submodule update --init --recursive && cd ..   # sau khi clone
cast wallet import nftmaps-deployer --interactive                    # lưu private key vào keystore, làm 1 lần
scripts/deploy-fuji.sh                                               # test → deploy → ghi địa chỉ vào ios/NFTMaps/Config.swift
VERIFY=1 scripts/deploy-fuji.sh                                      # (tuỳ chọn) verify source trên Snowtrace luôn
```

Script tự lấy mật khẩu keystore từ macOS Keychain nếu có mục service `foundry-keystore`, account `nftmaps-deployer`; không có thì forge hỏi. Lưu mật khẩu vào Keychain: `security add-generic-password -s foundry-keystore -a nftmaps-deployer -w`.

OpenZeppelin được ghim ở **v5.6.1** và đặt `evm_version = "cancun"`. Lý do: từ OZ 5.7, thư viện dùng opcode `CLZ` (Osaka) mà Fuji chưa hỗ trợ.

### 2. Pimlico (bundler + paymaster)

Key không nằm trong source. Chép `ios/Config/Local.xcconfig.example` thành `ios/Config/Local.xcconfig` (đã gitignore) rồi điền:

```
PIMLICO_API_KEY = pim_...          # https://dashboard.pimlico.io
PIMLICO_POLICY_ID = sp_...         # sponsorship policy cho Fuji
NULLMAPS_API_KEY = ...             # API_KEY trong nullmaps/.env
```

Lúc build, các giá trị này được ghi vào Info.plist và `Config.swift` đọc ra từ đó.

### 3. NullMaps chạy local

Dẫn đường đi bộ (vòng gợi ý, nút Dẫn đường) và tên phường (bảng xếp hạng) lấy từ [NullMaps](https://github.com/tuantqse90/nullmaps) tự host trên máy Mac:

```bash
cd ../nullmaps && docker compose up -d     # gateway :8088, adapter :8010, Valhalla, geocoder
```

- **Simulator** gọi thẳng `http://127.0.0.1:8088`, đây là giá trị mặc định trong `ios/Config/App.xcconfig`.
- **iPhone thật** cùng Wi-Fi: thêm `NULLMAPS_URL = http:/$()/<tên-mac>.local:8010` vào `Local.xcconfig`. Gateway chỉ nghe 127.0.0.1, còn adapter mở ra mạng LAN.
- Thiếu key hoặc NullMaps tắt thì app tự lùi về Apple MapKit (`MKDirections`, `CLGeocoder`).
- Nền bản đồ vẫn là MapKit.
- Kiểm tra nhanh: `NullMapsLiveTests` gọi NullMaps thật, tự bỏ qua nếu chưa cấu hình.

App chỉ dành cho một người chạy: không có server, không có "ai đang chạy", thả tim hay boss chung.

### 4. Chạy app

```bash
cd ios
xcodegen generate     # chạy lại mỗi khi thêm/xoá file Swift
open NFTMaps.xcodeproj
```

Trên Simulator:
- Đặt vị trí giả ở menu **Features → Location**.
- Simulator không có camera. Thêm ảnh chó/mèo vào thư viện bằng `xcrun simctl addmedia booted ~/Downloads/cat.jpg`, rồi trong màn bắt bấm **Chọn ảnh để chơi**. Kéo-thả chuột nhanh lên phía vòng ngắm để ném bóng.

## Ví hoạt động thế nào

1. **Đăng nhập:** `privateKey = PBKDF2-HMAC-SHA256(password, "nftmaps-v1:" + username, 600k vòng)`. Không cần server: nhập đúng username và mật khẩu trên máy khác vẫn ra đúng ví cũ. Key được lưu vào Keychain để lần sau tự đăng nhập. iOS sẽ gợi ý lưu mật khẩu vào Keychain, nên lưu vì quên mật khẩu là mất ví.
2. **Smart account:** địa chỉ ví là `MapAccountFactory.getAddress(owner)`. Contract chỉ thực sự được deploy ở UserOperation đầu tiên, thông qua `initCode`.
3. **Mint:** app dựng UserOperation gọi `MapAccount.execute → MapNFT.mint`. Paymaster của Pimlico trả gas, app tự ký bằng key trong máy, rồi bundler gửi giao dịch lên EntryPoint v0.8.

> ⚠️ Ví dẫn xuất từ mật khẩu (brainwallet) chỉ hợp cho testnet và demo. Ai đoán được username + mật khẩu sẽ lấy được ví. Gõ sai mật khẩu không báo lỗi mà ra một ví mới, trống.

## Màn bắt chó/mèo

1. Bấm **Đi bắt chó/mèo!** để mở camera. Model nhận diện khoảng 6 lần mỗi giây; thấy bé thì hiện vòng ngắm xoay kèm nhãn "Mèo · 82%".
2. **Vuốt** quả bóng lên phía bé. Hướng vuốt quyết định bóng lệch trái hay phải. Lực vuốt quyết định độ xa: yếu thì bóng rơi giữa đường, quá mạnh thì bay vọt qua.
3. Bóng rơi trong vòng ngắm là trúng. Càng gần tâm càng dễ bắt: "Trúng tâm!" chắc chắn bắt được, "Ném đẹp!" 90%, "Trúng rồi!" 75%.
4. Bóng lắc 3 lần (3 chấm sáng dần), sau đó là "Bắt được rồi!" kèm pháo hoa, hoặc bé thoát ra và bạn ném lại. Ảnh dùng làm NFT là đúng khung hình lúc bóng trúng, và model nhận diện lại trên chính ảnh đó.
5. Thẻ bắt được có nút **Đặt tên & mint NFT**. Bấm vào sẽ mở sheet mint ngay trên bản đồ.

Không có camera (Simulator) hoặc muốn dùng ảnh có sẵn thì bấm nút ảnh ở góc phải để chọn ảnh. Cách chơi giống hệt, chỉ là trên ảnh tĩnh.

## Nhận diện chó/mèo

- **Model:** `VNRecognizeAnimalsRequest` của Apple Vision, có sẵn trong iOS, chạy offline trên máy. Không cần train hay tải model. Ngưỡng tin cậy là 0.5; ảnh chó/mèo rõ thường đạt 0.7–0.9. (`Core/PetDetector.swift`)
- **Ảnh on-chain:** app cắt hình vuông quanh con vật rồi nén JPEG 256px, tối đa 12KB (thực tế khoảng 10KB), không mang EXIF/GPS. Ảnh quá nhiều chi tiết thì tự lùi xuống kích thước hoặc chất lượng thấp hơn. Ảnh lưu thẳng vào contract qua SSTORE2, không cần IPFS. Mỗi lần mint tốn khoảng 2.6M gas, do paymaster trả. (`Core/PetPhoto.swift`)
- **Metadata:** `tokenURI` trả JSON gồm ảnh và các thuộc tính Species / Confidence / Location, được dựng hoàn toàn on-chain nên ví và marketplace đọc thẳng được.
- **Giới hạn:** contract chỉ ghi lại kết quả mà app gửi lên. Ai gọi contract trực tiếp, không qua app, vẫn mint được ảnh bất kỳ, vì chain không tự kiểm chứng được nội dung ảnh.

## Test

```bash
cd contracts && forge test                                   # 27 test contract
cd ios && xcodebuild test -project NFTMaps.xcodeproj -scheme NFTMaps \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:NFTMapsTests                                 # 38 unit test app (1 test gọi NullMaps local)
```

Tour giao diện (đăng nhập ví demo, đi qua các tab, chạy thử một vòng, lưu ảnh màn hình):

```bash
xcrun simctl privacy booted grant location-always com.hackbuilder.nftmaps   # sau khi cài app
xcrun simctl location booted set 10.7752,106.6929
TEST_RUNNER_SHOTS_DIR=/tmp/shots xcodebuild test -project NFTMaps.xcodeproj -scheme NFTMaps \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:NFTMapsUITests
```

### Chạy app với chain local (chỉ bản Debug)

Để thử toàn luồng mà không đụng Fuji thật, đặt các biến môi trường sau trong scheme (**Edit Scheme → Run → Environment Variables**). Bản Release bỏ qua các biến này.

| Biến | Ý nghĩa |
|---|---|
| `NFTMAPS_RPC_URL` | RPC thay cho Fuji, ví dụ `anvil --fork-url https://api.avax-test.network/ext/bc/C/rpc` → `http://127.0.0.1:8545` |
| `NFTMAPS_CONTRACT`, `NFTMAPS_FACTORY`, `NFTMAPS_RUN_NFT` | địa chỉ MapNFT / MapAccountFactory / RunNFT deploy trên chain đó |
| `NFTMAPS_BUNDLER_URL` | bundler ERC-4337 thay cho Pimlico |
| `PIMLICO_API_KEY`, `PIMLICO_POLICY_ID`, `NULLMAPS_URL`, `NULLMAPS_API_KEY` | ghi đè giá trị trong `Local.xcconfig` |
| `NFTMAPS_CATCH_PHOTO` | đường dẫn một ảnh: màn bắt dùng luôn ảnh này thay cho camera |
