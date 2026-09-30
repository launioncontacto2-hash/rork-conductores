# DORI Vehicle Agent — Golden v0.6

- SHA: `0f3fb47968822df8b1834ad11bac5bbe8fe02d5e`
- Workflow run: `36672235553`; job `109750014622`; artifact `11079070067`
- APK SHA256: `2bd47da7b83b9958a5e49438b0bbd9c2d012dd037fee23d8053b0916541f08e4`
- Package `mx.dori.vehicleagent.probe`; version `0.6`/code `6`; min 24; target 33; compile 36
- V1/V2/V3: true; certificate SHA256 `2bf833e518ba94246e7d15fa018f1fedecc3866cdc5ad0d961db2ad1d3369e01`
- Architecture: fixed `/system/bin/service` fallback through APP_UID, strictly read-only.
- Physical proof: SOC 94.0%, ODO 15243.0 km, channel `SERVICE_BINARY_APP_UID`, no ADB read during APK test.

Frozen by tag `dori-vehicle-agent-v0.6-golden`.
