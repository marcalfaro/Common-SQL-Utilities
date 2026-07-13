DECLARE @SearchName nvarchar(256) = N'fCore_GetRotEndUserBySO';
DECLARE @ExactMatch bit = 0;
-- 1 = exact object-name match
-- 0 = partial match using LIKE '%ObjectNameHere%'

DROP TABLE IF EXISTS #ObjectSearchResults;

CREATE TABLE #ObjectSearchResults
(
    ServerName        sysname,
    DatabaseName      sysname,
    SchemaName        sysname,
    ObjectName        sysname,
    ObjectType        nvarchar(100),
    ObjectTypeCode    char(2),
    FullyQualifiedName nvarchar(1000),
    CreateDate        datetime,
    ModifyDate        datetime
);

DECLARE
    @DatabaseName sysname,
    @Sql          nvarchar(max);

DECLARE DatabaseCursor CURSOR LOCAL FAST_FORWARD FOR
SELECT [name]
FROM sys.databases
WHERE [state_desc] = N'ONLINE'
  AND [database_id] > 4            -- Excludes master, tempdb, model, msdb
  AND HAS_DBACCESS([name]) = 1
ORDER BY [name];

OPEN DatabaseCursor;

FETCH NEXT FROM DatabaseCursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'
    BEGIN TRY
        INSERT INTO #ObjectSearchResults
        (
            ServerName,
            DatabaseName,
            SchemaName,
            ObjectName,
            ObjectType,
            ObjectTypeCode,
            FullyQualifiedName,
            CreateDate,
            ModifyDate
        )
        SELECT
            CAST(SERVERPROPERTY(''ServerName'') AS sysname),
            N' + QUOTENAME(@DatabaseName, '''') + N',
            s.[name],
            o.[name],
            CASE o.[type]
                WHEN ''U''  THEN ''Table''
                WHEN ''P''  THEN ''SQL Stored Procedure''
                WHEN ''PC'' THEN ''CLR Stored Procedure''
                WHEN ''FN'' THEN ''SQL Scalar-Valued Function''
                WHEN ''FS'' THEN ''CLR Scalar-Valued Function''
                WHEN ''IF'' THEN ''Inline Table-Valued Function''
                WHEN ''TF'' THEN ''Multi-Statement Table-Valued Function''
                WHEN ''FT'' THEN ''CLR Table-Valued Function''
                ELSE o.[type_desc]
            END,
            o.[type],
            QUOTENAME(CAST(SERVERPROPERTY(''ServerName'') AS sysname))
                + ''.'' + QUOTENAME(N' + QUOTENAME(@DatabaseName, '''') + N')
                + ''.'' + QUOTENAME(s.[name])
                + ''.'' + QUOTENAME(o.[name]),
            o.[create_date],
            o.[modify_date]
        FROM ' + QUOTENAME(@DatabaseName) + N'.sys.objects AS o
        INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas AS s
            ON s.[schema_id] = o.[schema_id]
        WHERE o.[is_ms_shipped] = 0
          AND o.[type] IN
          (
              ''U'',                 -- Table
              ''P'', ''PC'',         -- Stored procedures
              ''FN'', ''FS'',        -- Scalar-valued functions
              ''IF'', ''TF'', ''FT'' -- Table-valued functions
          )
          AND
          (
              (@ExactMatch = 1 AND o.[name] = @SearchName)
              OR
              (@ExactMatch = 0 AND o.[name] LIKE N''%'' + @SearchName + N''%'')
          );
    END TRY
    BEGIN CATCH
        PRINT N''Could not search database ' + REPLACE(@DatabaseName, '''', '''''') + N': ''
            + ERROR_MESSAGE();
    END CATCH;';

    EXEC sys.sp_executesql
        @Sql,
        N'@SearchName nvarchar(256), @ExactMatch bit',
        @SearchName = @SearchName,
        @ExactMatch = @ExactMatch;

    FETCH NEXT FROM DatabaseCursor INTO @DatabaseName;
END;

CLOSE DatabaseCursor;
DEALLOCATE DatabaseCursor;

SELECT
    ServerName,
    DatabaseName,
    SchemaName,
    ObjectName,
    ObjectType,
    FullyQualifiedName,
    CreateDate,
    ModifyDate
FROM #ObjectSearchResults
ORDER BY
    DatabaseName,
    SchemaName,
    ObjectType,
    ObjectName;
