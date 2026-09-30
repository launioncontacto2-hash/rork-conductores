# DORI Vehicle Telemetry Catalog

Signals are compiled in a static table. The app accepts no transaction, device, FID, or command input.

## CERTIFIED_PHYSICAL
- SOC: device 1014, FID 1246777400, tx 7, float, percent.
- ODO: device 1014, FID 1246765072, tx 5, int/10, km.
- TPMS pressure FL/FR/RL/RR: device 1016, tx 5, FIDs -1728052956/-1728052952/-1728052948/-1728052944.

## OBSERVED_VALID
POWER_KW, TOTAL_ELECTRIC_KWH, BATTERY_REMAIN_KWH, POWER_STATE, GEAR, DRIVE_MODE, SOH, 12V, MAX_CELL, MIN_CELL, MAX_BAT_TEMP, MIN_BAT_TEMP, HV_VOLTAGE, HV_CURRENT, INSULATION, BMS_MAX_CHARGE, FL/FR/RL/RR_TEMPERATURE.

## CANDIDATE
WORK_MODE, BMS_MAX_DISCHARGE_ALLOW, CHARGE_GUN_STATE, BMS_CHARGE_STATE, CHARGING_TYPE, CHARGING_SESSION_KWH, FRONT_MOTOR_TEMP, FRONT_INVERTER_TEMP, FRONT_MOTOR_RPM, ACCELERATOR, BRAKE.

## UNSUPPORTED_SENTINEL
TRUNK and CABIN_TEMP sentinel values are not shown. `0x0000ffff` and `0xffffd8e5` render `UNAVAILABLE`.

All reads use only autoservice transactions 5 (integer) and 7 (float), via fixed ProcessBuilder arguments. No network, history, upload, control, or write operation exists.
