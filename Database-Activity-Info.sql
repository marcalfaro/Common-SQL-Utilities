;WITH IndexActivity AS
(
    SELECT
        database_id,
        MAX(last_user_seek)   AS LastUserSeek,
        MAX(last_user_scan)   AS LastUserScan,
        MAX(last_user_lookup) AS LastUserLookup,
        MAX(last_user_update) AS LastUserUpdate
    FROM sys.dm_db_index_usage_stats
    GROUP BY database_id
),
CurrentConnections AS
(
    SELECT
        database_id,
        COUNT(*) AS CurrentConnectionCount,
        MAX(last_request_start_time) AS LastConnectedRequestStart,
        MAX(last_request_end_time)   AS LastConnectedRequestEnd
    FROM sys.dm_exec_sessions
    WHERE is_user_process = 1
      AND database_id IS NOT NULL
    GROUP BY database_id
),
ActiveRequests AS
(
    SELECT
        database_id,
        COUNT(*) AS ActiveRequestCount,
        MAX(start_time) AS LatestActiveRequestStart
    FROM sys.dm_exec_requests
    WHERE session_id <> @@SPID
      AND database_id IS NOT NULL
    GROUP BY database_id
),
RestoreHistory AS
(
    SELECT
        destination_database_name,
        MAX(restore_date) AS LastRestoreDate
    FROM msdb.dbo.restorehistory
    GROUP BY destination_database_name
),
BackupHistory AS
(
    SELECT
        database_name,
        MAX(CASE WHEN type = 'D' THEN backup_finish_date END)
            AS LastFullBackup,
        MAX(CASE WHEN type = 'I' THEN backup_finish_date END)
            AS LastDifferentialBackup,
        MAX(CASE WHEN type = 'L' THEN backup_finish_date END)
            AS LastLogBackup
    FROM msdb.dbo.backupset
    GROUP BY database_name
)
SELECT
    d.database_id,
    d.name AS DatabaseName,
    d.state_desc AS DatabaseState,
    d.recovery_model_desc AS RecoveryModel,
    d.create_date AS DatabaseCreateDate,

    rh.LastRestoreDate,

    ia.LastUserSeek,
    ia.LastUserScan,
    ia.LastUserLookup,
    ia.LastUserUpdate,

    activity.LastRecordedActivity,

    ISNULL(cc.CurrentConnectionCount, 0) AS CurrentConnectionCount,
    cc.LastConnectedRequestStart,
    cc.LastConnectedRequestEnd,

    ISNULL(ar.ActiveRequestCount, 0) AS ActiveRequestCount,
    ar.LatestActiveRequestStart,

    bh.LastFullBackup,
    bh.LastDifferentialBackup,
    bh.LastLogBackup,

    osi.sqlserver_start_time AS ActivityTrackingStartTime,

    CASE
        WHEN ar.ActiveRequestCount > 0
            THEN 'Currently active'
        WHEN cc.CurrentConnectionCount > 0
            THEN 'Connected but not currently executing'
        WHEN activity.LastRecordedActivity IS NOT NULL
            THEN 'Previous activity recorded'
        ELSE 'No activity recorded since DMV reset'
    END AS ActivityStatus

FROM sys.databases AS d

CROSS JOIN sys.dm_os_sys_info AS osi

LEFT JOIN IndexActivity AS ia
    ON ia.database_id = d.database_id

LEFT JOIN CurrentConnections AS cc
    ON cc.database_id = d.database_id

LEFT JOIN ActiveRequests AS ar
    ON ar.database_id = d.database_id

LEFT JOIN RestoreHistory AS rh
    ON rh.destination_database_name = d.name

LEFT JOIN BackupHistory AS bh
    ON bh.database_name = d.name

OUTER APPLY
(
    SELECT MAX(ActivityDate) AS LastRecordedActivity
    FROM
    (
        VALUES
            (ia.LastUserSeek),
            (ia.LastUserScan),
            (ia.LastUserLookup),
            (ia.LastUserUpdate),
            (cc.LastConnectedRequestStart),
            (cc.LastConnectedRequestEnd),
            (ar.LatestActiveRequestStart)
    ) AS ActivityDates(ActivityDate)
) AS activity

ORDER BY
    activity.LastRecordedActivity DESC,
    d.name;
