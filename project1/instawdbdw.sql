/*============================================================================
  File:     instawdb.sql

  Summary:  Creates the crimeAtlanta sample database. 

  Modified Date:	April 20, 2023
  Contributors:	Ronjon Kundu(23215183)

------------------------------------------------------------------------------
  Original Data file is provided through LMS,UWA by the unit coordinator
  
  THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY
  KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
  IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
  PARTICULAR PURPOSE.
============================================================================*/

/*
 * HOW TO RUN THIS SCRIPT:
 *
 * 1. Enable full-text search on your SQL Server instance. 
 *
 * 2. Open the script inside SQL Server Management Studio and enable SQLCMD mode. 
 *    This option is in the Query menu.
 *
 * 3. Copy this script and the install files to C:\Samples\AdventureWorksDW, or
 *    set the following environment variable to your own data path.
 */
 :setvar SqlSamplesSourceDataPath "D:\uwa\Data_Warehousing\project1\"

/*
 * 4. Append the SQL Server version number to database name if you want to
 *    differentiate it from other installs of AdventureWorksDW
 */

:setvar DatabaseName "crimeinAtlantaproject1"

/* Execute the script
 */

IF '$(SqlSamplesSourceDataPath)' IS NULL OR '$(SqlSamplesSourceDataPath)' = ''
BEGIN
	RAISERROR(N'The variable SqlSamplesSourceDataPath must be defined.', 16, 127) WITH NOWAIT
	RETURN
END;


SET NOCOUNT OFF;
GO

PRINT CONVERT(varchar(1000), @@VERSION);
GO

PRINT '';
PRINT 'Started - ' + CONVERT(varchar, GETDATE(), 121);
GO

USE [master];
GO


-- ****************************************
-- Drop Database
-- ****************************************
PRINT '';
PRINT '*** Dropping Database';
GO

IF EXISTS (SELECT [name] FROM [master].[sys].[databases] WHERE [name] = N'$(DatabaseName)')
    DROP DATABASE $(DatabaseName);

-- If the database has any other open connections close the network connection.
IF @@ERROR = 3702 
    RAISERROR('$(DatabaseName) database cannot be dropped because there are still other open connections', 127, 127) WITH NOWAIT, LOG;
GO

-- ****************************************
-- Create Database
-- ****************************************
PRINT '';
PRINT '*** Creating Database';
GO

CREATE DATABASE $(DatabaseName);
GO

PRINT '';
PRINT '*** Checking for $(DatabaseName) Database';
/* CHECK FOR DATABASE IF IT DOESN'T EXISTS, DO NOT RUN THE REST OF THE SCRIPT */
IF NOT EXISTS (SELECT TOP 1 1 FROM sys.databases WHERE name = N'$(DatabaseName)')
BEGIN
PRINT '*******************************************************************************************************************************************************************'
+char(10)+'********$(DatabaseName) Database does not exist.  Make sure that the script is being run in SQLCMD mode and that the variables have been correctly set.*********'
+char(10)+'*******************************************************************************************************************************************************************';
SET NOEXEC ON;
END
GO

ALTER DATABASE $(DatabaseName) 
SET RECOVERY SIMPLE, 
    ANSI_NULLS ON, 
    ANSI_PADDING ON, 
    ANSI_WARNINGS ON, 
    ARITHABORT ON, 
    CONCAT_NULL_YIELDS_NULL ON, 
    QUOTED_IDENTIFIER ON, 
    NUMERIC_ROUNDABORT OFF, 
    PAGE_VERIFY CHECKSUM, 
    ALLOW_SNAPSHOT_ISOLATION OFF;
GO

USE $(DatabaseName);
GO


-- ****************************************
-- Create DDL Trigger for Database
-- ****************************************
PRINT '';
PRINT '*** Creating DDL Trigger for Database';
GO

-- Create table to store database object creation messages
-- *** WARNING:  THIS TABLE IS INTENTIONALLY A HEAP - DO NOT ADD A PRIMARY KEY ***
CREATE TABLE [dbo].[DatabaseLog](
    [DatabaseLogID] [int] IDENTITY (1, 1) NOT NULL,
    [PostTime] [datetime] NOT NULL, 
    [DatabaseUser] [sysname] NOT NULL, 
    [Event] [sysname] NOT NULL, 
    [Schema] [sysname] NULL, 
    [Object] [sysname] NULL, 
    [TSQL] [nvarchar](max) NOT NULL, 
    [XmlEvent] [xml] NOT NULL
) ON [PRIMARY];
GO

CREATE TRIGGER [ddlDatabaseTriggerLog] ON DATABASE 
FOR DDL_DATABASE_LEVEL_EVENTS AS 
BEGIN
    SET NOCOUNT ON;

    DECLARE @data XML;
    DECLARE @schema sysname;
    DECLARE @object sysname;
    DECLARE @eventType sysname;

    SET @data = EVENTDATA();
    SET @eventType = @data.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname');
    SET @schema = @data.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname');
    SET @object = @data.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname') 

    IF @object IS NOT NULL
        PRINT '  ' + @eventType + ' - ' + @schema + '.' + @object;
    ELSE
        PRINT '  ' + @eventType + ' - ' + @schema;

    IF @eventType IS NULL
        PRINT CONVERT(nvarchar(max), @data);

    INSERT [dbo].[DatabaseLog] 
        (
        [PostTime], 
        [DatabaseUser], 
        [Event], 
        [Schema], 
        [Object], 
        [TSQL], 
        [XmlEvent]
        ) 
    VALUES 
        (
        GETDATE(), 
        CONVERT(sysname, CURRENT_USER), 
        @eventType, 
        CONVERT(sysname, @schema), 
        CONVERT(sysname, @object), 
        @data.value('(/EVENT_INSTANCE/TSQLCommand)[1]', 'nvarchar(max)'), 
        @data
        );
END;
GO



-- ******************************************************
-- Create User Defined Functions
-- ******************************************************
-- Builds an ISO 8601 format date from a year, month, and day specified as integers.
-- This format of date should parse correctly regardless of SET DATEFORMAT and SET LANGUAGE.
-- See SQL Server Books Online for more details.
CREATE FUNCTION [dbo].[udfBuildISO8601Date] (@year int, @month int, @day int)
RETURNS datetime
AS 
BEGIN
	RETURN cast(convert(varchar, @year) + '-' + [dbo].[udfTwoDigitZeroFill](@month) 
	    + '-' + [dbo].[udfTwoDigitZeroFill](@day) + 'T00:00:00' 
	    as datetime);
END;
GO


CREATE FUNCTION [dbo].[udfMinimumDate] (
    @x DATETIME, 
    @y DATETIME
) RETURNS DATETIME
AS
BEGIN
    DECLARE @z DATETIME

    IF @x <= @y 
        SET @z = @x 
    ELSE 
        SET @z = @y

    RETURN(@z)
END;
GO

-- Converts the specified integer (which should be < 100 and > -1)
-- into a two character string, zero filling from the left 
-- if the number is < 10.
CREATE FUNCTION [dbo].[udfTwoDigitZeroFill] (@number int) 
RETURNS char(2)
AS
BEGIN
	DECLARE @result char(2);
	IF @number > 9 
		SET @result = convert(char(2), @number);
	ELSE
		SET @result = convert(char(2), '0' + convert(varchar, @number));
	RETURN @result;
END;
GO

-- ******************************************************
-- Create tables
-- ******************************************************
PRINT '';
PRINT '*** Creating Tables';
GO

CREATE TABLE [dbo].[crimeBuildVersion](
	[DBVersion] [nvarchar](50) NULL,
	[VersionDate] [datetime] NULL
) ON [PRIMARY];
GO

CREATE TABLE [dbo].[DimLocation](
	[locationid] [int] IDENTITY(1,1) NOT NULL,
	[location] [nvarchar](100) NULL,
	[neighborhoodid] [int] NOT NULL,
	[npuid] [int] NOT NULL,
	[lat] [nvarchar](300) NOT NULL,
	[long] [nvarchar](300) NOT NULL,
	[road] [nvarchar](300) NOT NULL,
	[neighbourhood_lookupid] [int] NOT NULL,
	[postcode] [int] NOT NULL,
	[county] [nvarchar](200) NOT NULL 
) ON [PRIMARY];
GO

CREATE TABLE [dbo].[DimNeighborhood](
	[neighborhoodid] [int] IDENTITY(1,1) NOT NULL,
	[neighborhood] [nvarchar](100) NOT NULL
) ON [PRIMARY];
GO

CREATE TABLE [dbo].[DimNeighborhoodlookup](
	[neighbourhood_lookupid] [int] IDENTITY(1,1) NOT NULL,
	[neighbourhood_lookup] [nvarchar](100) NOT NULL
) ON [PRIMARY];
GO

CREATE TABLE [dbo].[DimNPU](
	[npuid] [int] IDENTITY(1,1) NOT NULL,
	[npu] [nchar](3) NOT NULL
) ON [PRIMARY];
GO

CREATE TABLE [dbo].[DimBEAT](
	[BEATid] [int] IDENTITY(1,1) NOT NULL,
	[BEAT] [int] NOT NULL
) ON [PRIMARY];
GO

CREATE TABLE [dbo].[DimZONE](
	[ZONEid] [int] IDENTITY(1,1) NOT NULL,
	[ZONE] [int] NOT NULL
) ON [PRIMARY];
GO

CREATE TABLE [dbo].[Dimcrime](
	[crimeid_x] [int] IDENTITY(1,1) NOT NULL,
	[crime] [nvarchar](100) NOT NULL
) ON [PRIMARY];
GO


CREATE TABLE [dbo].[DimDate](
	[dateid] [int] NOT NULL,
	[DayNumberOfMonth] [tinyint] NOT NULL,
	[MonthNumberOfYear] [tinyint] NOT NULL,
	[CalendarQuarter] [tinyint] NOT NULL,
	[CalendarYear] [smallint] NOT NULL
) ON [PRIMARY];
GO


CREATE TABLE [dbo].[FactCrime](
	[number] [int] NOT NULL,
	[locationid] [int] NOT NULL,
	[BEATid] [int] NOT NULL,
	[ZONEid] [int] NOT NULL,
	[dateid] [int] NOT NULL,
	[crimeid_x] [int] NOT NULL,
	[count_crime] [int] NOT NULL,

) ON [PRIMARY];
GO

SET ANSI_PADDING ON
GO

EXEC sys.sp_addextendedproperty @name=N'microsoft_database_tools_support', @value=1 , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'sysdiagrams'
GO


-- ******************************************************
-- Load data
-- ******************************************************
PRINT '';
PRINT '*** Loading Data';
GO


PRINT 'Loading [dbo].[DimLocation]';

BULK INSERT [dbo].[DimLocation] FROM '$(SqlSamplesSourceDataPath)crime_dimlocation.csv'
WITH (
    CHECK_CONSTRAINTS,
   -- CODEPAGE='ACP',
	FIRSTROW = 2,
    FIELDTERMINATOR= ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[DimNeighborhood]';

BULK INSERT [dbo].[DimNeighborhood] FROM '$(SqlSamplesSourceDataPath)crime_dimneighborhood.csv'
WITH (
    CHECK_CONSTRAINTS,
   -- CODEPAGE='ACP',
    FIRSTROW = 2,
    FIELDTERMINATOR= ',',
    ROWTERMINATOR = '0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[DimNeighborhoodlookup]';

BULK INSERT[dbo].[DimNeighborhoodlookup] FROM '$(SqlSamplesSourceDataPath)crime_dimneighborhoodlookup.csv'
WITH (
    CHECK_CONSTRAINTS,
   -- CODEPAGE='ACP',
    FIRSTROW = 2,
    FIELDTERMINATOR=',',
    ROWTERMINATOR='0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[DimNPU]';

BULK INSERT [dbo].[DimNPU] FROM '$(SqlSamplesSourceDataPath)crime_dimnpu.csv'
WITH (
    CHECK_CONSTRAINTS,
    --CODEPAGE='ACP',
	FIRSTROW = 2,
    FIELDTERMINATOR=',',
    ROWTERMINATOR='0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[DimBEAT]';

BULK INSERT [dbo].[DimBEAT] FROM '$(SqlSamplesSourceDataPath)crime_dimbeat.csv'
WITH (
    CHECK_CONSTRAINTS,
    --CODEPAGE='ACP',
	FIRSTROW = 2,
    FIELDTERMINATOR=',',
    ROWTERMINATOR='0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[DimZONE]';

BULK INSERT [dbo].[DimZONE] FROM '$(SqlSamplesSourceDataPath)crime_dimzone.csv'
WITH (
    CHECK_CONSTRAINTS,
   -- CODEPAGE='ACP',
    FIRSTROW = 2,
    FIELDTERMINATOR=',',
    ROWTERMINATOR='0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[Dimcrime]';

BULK INSERT [dbo].[Dimcrime] FROM '$(SqlSamplesSourceDataPath)crime_dimcrime.csv'
WITH (
    CHECK_CONSTRAINTS,
    --CODEPAGE='ACP',
	FIRSTROW = 2,
    FIELDTERMINATOR=',',
    ROWTERMINATOR='0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[DimDate]';

BULK INSERT [dbo].[DimDate] FROM '$(SqlSamplesSourceDataPath)crime_dimdate.csv'
WITH (
    CHECK_CONSTRAINTS,
    --CODEPAGE='ACP',
	FIRSTROW = 2,
    FIELDTERMINATOR=',',
    ROWTERMINATOR='0x0a',
    KEEPIDENTITY,
    TABLOCK
);

PRINT 'Loading [dbo].[FactCrime]';

BULK INSERT [dbo].[FactCrime] FROM '$(SqlSamplesSourceDataPath)crime_factcrime.csv'
WITH (
    CHECK_CONSTRAINTS,
    --CODEPAGE='ACP',
	FIRSTROW = 2,
    FIELDTERMINATOR=',',
    ROWTERMINATOR='0x0a',
    KEEPIDENTITY,
    TABLOCK
);


-- ******************************************************
-- Add Primary Keys
-- ******************************************************
PRINT '';
PRINT '*** Adding Primary Keys';
GO

SET QUOTED_IDENTIFIER ON;

ALTER TABLE [dbo].[DimLocation] WITH CHECK ADD 
    CONSTRAINT [PK_DimLocation] PRIMARY KEY CLUSTERED
	(
	[locationid]
	) ON [PRIMARY];
GO


ALTER TABLE [dbo].[DimNeighborhood] WITH CHECK ADD 
    CONSTRAINT [PK_DimNeighborhood] PRIMARY KEY CLUSTERED 
    (
       [neighborhoodid]
    )  ON [PRIMARY];
GO

ALTER TABLE [dbo].[DimNeighborhoodlookup] WITH CHECK ADD 
    CONSTRAINT [PK_DimNeighborhoodlookup] PRIMARY KEY CLUSTERED
    (
        [neighbourhood_lookupid]
    )  ON [PRIMARY];
GO


ALTER TABLE [dbo].[DimNPU] WITH CHECK ADD 
    CONSTRAINT [PK_DimNPU] PRIMARY KEY CLUSTERED 
    (
        [npuid]
    )  ON [PRIMARY];
GO

ALTER TABLE [dbo].[DimBEAT] WITH CHECK ADD 
    CONSTRAINT [PK_DimBEAT] PRIMARY KEY CLUSTERED 
    (
        [BEATid]
    )  ON [PRIMARY];
GO

ALTER TABLE [dbo].[DimZONE] WITH CHECK ADD 
    CONSTRAINT [PK_DimZONE] PRIMARY KEY CLUSTERED 
    (
       [ZONEid]
    )  ON [PRIMARY];
GO

ALTER TABLE [dbo].[Dimcrime] WITH CHECK ADD 
    CONSTRAINT [PK_Dimcrime] PRIMARY KEY CLUSTERED 
    (
       [crimeid_x]
    )  ON [PRIMARY];
GO

ALTER TABLE [dbo].[DimDate] WITH CHECK ADD 
    CONSTRAINT [PK_DimDate] PRIMARY KEY CLUSTERED 
    (
       [dateid]
    )  ON [PRIMARY];
GO


-- ****************************************
-- Create Foreign key constraints
-- ****************************************
PRINT '';
PRINT '*** Creating Foreign Key Constraints';
GO

ALTER TABLE [dbo].[DimLocation] ADD 
    CONSTRAINT [FK_DimLocation_Dimneighborhood] FOREIGN KEY 
    (
        [neighborhoodid]
    ) REFERENCES [dbo].[DimNeighborhood] ([neighborhoodid]),
	CONSTRAINT [FK_DimLocation_DimNPU] FOREIGN KEY 
    (
        [npuid]
    ) REFERENCES [dbo].[DimNPU] ([npuid]),
	CONSTRAINT [FK_DimLocation_DimNeighborhoodlookup] FOREIGN KEY 
    (
        [neighbourhood_lookupid]
    ) REFERENCES [dbo].[DimNeighborhoodlookup] ([neighbourhood_lookupid]);

GO

ALTER TABLE [dbo].[FactCrime] ADD 
    CONSTRAINT [FK_FactCrime_DimLocation] FOREIGN KEY 
    (
        [locationid]
    ) REFERENCES [dbo].[DimLocation] ([locationid]),
	CONSTRAINT [FK_FactCrime_DimBEAT] FOREIGN KEY 
    (
        [BEATid]
    ) REFERENCES [dbo].[DimBEAT] ([BEATid]),
	CONSTRAINT [FK_FactCrime_DimZONE] FOREIGN KEY 
    (
        [ZONEid]
    ) REFERENCES [dbo].[DimZONE] ([ZONEid]),
	CONSTRAINT [FK_FactCrime_Dimcrime] FOREIGN KEY 
    (
        [crimeid_x]
    ) REFERENCES [dbo].[Dimcrime] ([crimeid_x]),
	CONSTRAINT [FK_FactCrime_DimDate] FOREIGN KEY 
    (
        [dateid]
    ) REFERENCES [dbo].[DimDate] ([dateid]);

GO


-- ****************************************
-- Drop DDL Trigger for Database
-- ****************************************
PRINT '';
PRINT '*** Disabling DDL Trigger for Database';
GO

DISABLE TRIGGER [ddlDatabaseTriggerLog] 
ON DATABASE;
GO

USE [master];
GO

PRINT 'Finished - ' + CONVERT(varchar, GETDATE(), 121);
GO

SET NOEXEC OFF