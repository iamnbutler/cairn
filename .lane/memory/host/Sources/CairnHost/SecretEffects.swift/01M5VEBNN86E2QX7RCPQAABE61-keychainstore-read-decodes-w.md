---
id: 01M5VEBNN86E2QX7RCPQAABE61
anchor: readNow
created: 2026-10-26T06:28:56Z
norm: '1'
---

KeychainStore.read decodes with String(validating:as:), not String(data:encoding:), which strips a leading BOM: the trusted fuzzer's keychain check caught it at N=20000
