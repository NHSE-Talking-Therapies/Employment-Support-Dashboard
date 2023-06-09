/****** Script for Employment Support Dashboard to produce the Presenteeism Table******/

--Base Table
--This table produces a version of the IDS606 table filtered for the three assessment questions (questions 7, 8 and 9) about presenteeism from the Institute for Medical Technology Assessment Productivity Cost Questionnaire,
--filtered for the latest audit IDs and the first and last responses to these questions labelled (through ranking) for use later in the query

IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral]') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral]
SELECT DISTINCT	
--this step of the query produces a table with all fields in the IDS606 table, filtered for the three assessment questions of interest,
--first and last responses to these questions are labelled (through ranking) for use later in the query, and provider codes are matched to provider names and corresponding region name
	sub.*
	,ph.Organisation_Name as [Provider Name]
	,ph.Region_Name as [Region Name]
	--This labels each record so that the last response to each assessment question has a value of 1. This is based on ordering each record with the same pathway ID and coded assessment tool type (i.e. assessment question) 
	--by the assessment tool completion date
	,ROW_NUMBER() OVER (PARTITION BY sub.PathwayID, sub.[CodedAssToolType] ORDER BY sub.[AssToolCompDate] desc) AS ROWID1
INTO [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral] 
FROM
	(SELECT DISTINCT --this subquery produces a table with all fields in the IDS606 table, filtered for the three assessment questions of interest and first responses to these questions have a value of 1
		a.*
		--This labels each record so that the first response to each assessment question has a value of 1. This is based on ordering each record with the same pathway ID and coded assessment tool type (i.e. assessment question) 
		--by the assessment tool completion date, time and unique ID for the IDS606 table
		,row_Number() OVER(PARTITION BY a.[PathwayID],a.[CodedAssToolType] ORDER BY a.[AssToolCompDate], a.[AssToolCompTime], a.[UniqueID_IDS606] desc) AS ROWID
		FROM
			(SELECT DISTINCT --this subquery produces a table with just the latest audit ID,the key fields for joining in the next part of the subquery and is filtered for the three assessment questions of interest
				MAX(c.AUDITID) AS AuditID
				,c.[AssToolCompDate]
				,c.[PathwayID]
				,c.[Unique_ServiceRequestID]
				,c.AssToolCompTime
			FROM [NHSE_IAPT_v2].[dbo].[IDS606_CodedScoredAssessmentReferral] c
			INNER JOIN [NHSE_IAPT_v2].[dbo].[IsLatest_SubmissionID] l ON c.[UniqueSubmissionID] = l.[UniqueSubmissionID] AND c.AuditId = l.AuditId
			WHERE (CodedAssToolType IN ('748161000000109','760741000000102','761051000000105'))	--The SNOMED CT concept IDs for question 7, 8 and 9 of the Institute for Medical Technology Assessment Productivity Cost Questionnaire
				AND IsLatest = 1	--for getting the latest data
			GROUP BY [AssToolCompDate], [PathwayID], [Unique_ServiceRequestID], AssToolCompTime, OrgID_Provider
			) x
		INNER JOIN [NHSE_IAPT_v2].[dbo].[IDS606_CodedScoredAssessmentReferral] a ON a.PathwayId = x.PathwayId AND a.[Unique_ServiceRequestID] = x.[Unique_ServiceRequestID] 
			AND a.AuditId = x.AuditID AND a.[AssToolCompDate] = x.[AssToolCompDate] AND a.AssToolCompTime = x.AssToolCompTime
		--inner join of the IDS606 table with table x leads to the IDS606 table with just the records with the latest audit ID
		WHERE (CodedAssToolType IN ('748161000000109','760741000000102','761051000000105'))	--The SNOMED CT concept IDs for question 7, 8 and 9 of the Institute for Medical Technology Assessment Productivity Cost Questionnaire
		) sub
LEFT JOIN [NHSE_Reference].[dbo].[tbl_Ref_ODS_Provider_Hierarchies] ph ON sub.OrgID_Provider = ph.Organisation_Code AND ph.Effective_To IS NULL
--Provider hierarchies table provides the names of the provider and region by matching on the provider code

-------------------------------------------------------------------------------------------------------------------------------------------------------
--Period start and period end are defined for the next part of the query:
USE [NHSE_IAPT_v2]

DECLARE @PeriodStart DATE
DECLARE @PeriodEnd DATE 
--For refreshing, the offset for getting the period start and end should be -1 to get the latest refreshed month
SET @PeriodStart = (SELECT DATEADD(MONTH,-1,MAX([ReportingPeriodStartDate])) FROM [IsLatest_SubmissionID])
SET @PeriodEnd = (SELECT eomonth(DATEADD(MONTH,-1,MAX([ReportingPeriodEndDate]))) FROM [dbo].[IsLatest_SubmissionID])

--The offset needs to be set for September 2020 (i.e. @PeriodStart -30 = -31 which is the offset of September 2020)
DECLARE @Offset int
SET @Offset=-30 
SET DATEFIRST 1

PRINT @PeriodStart
PRINT @PeriodEnd

--------------------------------------------------------------------------------------------------------------------------------------------------------
--Question 7: During the last 2 weeks have there been days in which you worked but during this time were bothered by physical or psychological problems?	
--Question 7 Base Table
--This table creates separate columns for the assessment score and assessment completion date for the first and last responses for question 7.
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]
SELECT 
	a.PathwayID
	,a.[Provider Name]
	,a.[Region Name]
	,a.CodedAssToolType
	,a.PersScore AS FirstPersScore
	,b.PersScore AS LastPersScore
	,b.AuditID
	,DATENAME(m, b.AssToolCompDate) + ' ' + CAST(DATEPART(yyyy, b.AssToolCompDate) AS varchar) as Month
	,a.AssToolCompDate AS FirstDate
	,b.AssToolCompDate AS LastDate
	,a.ROWID
	,b.ROWID1
INTO [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral] a 
	INNER JOIN [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral] b ON a.PathwayID = b.PathwayID
WHERE (a.CodedAssToolType = '748161000000109' AND a.ROWID = 1) AND (B.CodedAssToolType = '748161000000109' AND b.ROWID1 = 1 AND b.ROWID > 1)
AND b.AssToolCompDate BETWEEN DATEADD(MONTH, @Offset, @PeriodStart) AND @PeriodStart	
--Both table a and b are filtered for the coded assessment tool type of question 7 from the Institute for Medical Technology Assessment Productivity Cost Questionnaire.
--Table a is filtered to just have pathwayIDs where RowID is 1 i.e. the first appoinment to get a.PerScore as FirstPerScore.
--The same table is then inner joined as b. This is to then filter it on different conditions (RowID1 is 1 i.e. latest appointment and RowID is more than 1, meaning they have had more than 1 appointment).
--This means b.PerScore is LastPersScore

--Question 7 First Score	
--This table counts the distinct pathway IDs that have the same first response score to question 7, using the record level base table above ([NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]) 
--This table is re-run each month as the full time period needs to be used for the rankings to work correctly
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]
SELECT 
	CodedAssToolType
	,'FirstPersScore' as ScoreType
	,FirstPersScore as Score
	,COUNT(DISTINCT PathwayID) AS Count_Referrals
	,Month
	,[Provider Name]
	,[Region Name]
INTO [NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]
GROUP BY FirstPersScore
	,CodedAssToolType
	,Month
	,[Provider Name]
	,[Region Name]

--Question 7 Last Score
--This table counts the distinct pathway IDs that have the same last response score to question 7, using the record level base table above ([NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]) 
INSERT INTO [NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]
SELECT 
	CodedAssToolType
	,'LastPersScore' as ScoreType
	,LastPersScore as Score
	,COUNT(DISTINCT PathwayID) AS Count_Referrals
	,Month
	,[Provider Name]
	,[Region Name]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]
GROUP BY LastPersScore
	,CodedAssToolType
	,Month
	,[Provider Name]
	,[Region Name]

--------------------------------------------------------------------------------------------
--Question 8: How many days at work were you bothered by physical or psychological problems?
--Question 8 Base Table
--This table creates separate columns for the assessment score and assessment completion date for the first and last responses for question 8.
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]
SELECT 
	a.PathwayID
	,a.[Provider Name]
	,a.[Region Name]
	,a.CodedAssToolType
	,a.PersScore AS FirstPersScore
	,b.PersScore AS LastPersScore
	,b.AuditID
	,DATENAME(m, b.AssToolCompDate) + ' ' + CAST(DATEPART(yyyy, b.AssToolCompDate) AS varchar) as Month
	,a.AssToolCompDate AS FirstDate
	,b.AssToolCompDate AS LastDate
	,a.ROWID
	,b.ROWID1
INTO [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral] a 
	INNER JOIN [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral] b ON a.PathwayID = b.PathwayID
WHERE (a.CodedAssToolType = '760741000000102' AND a.ROWID = 1) AND (B.CodedAssToolType = '760741000000102' AND b.ROWID1 = 1 AND b.ROWID > 1)
	AND b.AssToolCompDate BETWEEN DATEADD(MONTH, @Offset, @PeriodStart) AND @PeriodStart	
--Both table a and b are filtered for the coded assessment tool type of question 8 from the Institute for Medical Technology Assessment Productivity Cost Questionnaire.
--Table a is filtered to just have pathwayIDs where RowID is 1 i.e. the first appoinment to get a.PerScore as FirstPerScore.
--The same table is then inner joined as b. This is to then filter it on different conditions (RowID1 is 1 i.e. latest appointment and RowID is more than 1, meaning they have had more than 1 appointment).
--This means b.PerScore is LastPersScore

--Question 8 First Score
--This table counts the distinct pathway IDs that have the same first response score to question 8, using the record level base table above ([NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]) 
INSERT INTO [NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]
SELECT 
	CodedAssToolType
	,'FirstPersScore' as ScoreType
	,FirstPersScore as Score
	,COUNT(DISTINCT PathwayID) AS Count_Referrals
	,Month
	,[Provider Name]
	,[Region Name]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]
GROUP BY FirstPersScore
	,CodedAssToolType
	,Month
	,[Provider Name]
	,[Region Name]

--Question 8 Last Score
--This table counts the distinct pathway IDs that have the same last response score to question 8, using the record level base table above ([NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]) 
INSERT INTO [NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]
SELECT 
	CodedAssToolType
	,'LastPersScore' as ScoreType
	,LastPersScore as Score
	,COUNT(DISTINCT PathwayID) AS Count_Referrals
	,Month
	,[Provider Name]
	,[Region Name]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]
GROUP BY LastPersScore
	,CodedAssToolType
	,Month
	,[Provider Name]
	,[Region Name]

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--Question 9: On the days that you were bothered by these problems, was it perhaps difficult to get as much work finished as you normally do? On these days how much work could you on average?
--Question 9 Base Table
--This table creates separate columns for the assessment score and assessment completion date for the first and last responses for question 9.
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]
SELECT 
	a.PathwayID
	,a.[Provider Name]
	,a.[Region Name]
	,a.CodedAssToolType
	,a.PersScore AS FirstPersScore
	,b.PersScore AS LastPersScore
	,b.AuditID
	,DATENAME(m, b.AssToolCompDate) + ' ' + CAST(DATEPART(yyyy, b.AssToolCompDate) AS varchar) as Month
	,a.AssToolCompDate AS FirstDate
	,b.AssToolCompDate AS LastDate
	,a.ROWID,b.ROWID1
INTO [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral] a 
	INNER JOIN [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral] b ON a.PathwayID = b.PathwayID
WHERE (a.CodedAssToolType = '761051000000105' AND a.ROWID = 1) AND (B.CodedAssToolType = '761051000000105' AND b.ROWID1 = 1 AND b.ROWID > 1)
	AND b.AssToolCompDate BETWEEN DATEADD(MONTH, @Offset, @PeriodStart) AND @PeriodStart

--Question 9 First Score
--This table counts the distinct pathway IDs that have the same first response score to question 9, using the record level base table above ([NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]) 
INSERT INTO [NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]
SELECT 
	CodedAssToolType
	,'FirstPersScore' as ScoreType
	,FirstPersScore as Score
	,COUNT(DISTINCT PathwayID) AS Count_Referrals
	,Month
	,[Provider Name]
	,[Region Name]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]
GROUP BY FirstPersScore
	,CodedAssToolType
	,Month
	,[Provider Name]
	,[Region Name]

--Question 9 Last Score
--This table counts the distinct pathway IDs that have the same last response score to question 9, using the record level base table above ([NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]) 
INSERT INTO [NHSE_Sandbox_MentalHealth].[dbo].[IAPT_PresenteeismCounts]
SELECT 
	CodedAssToolType
	,'LastPersScore' as ScoreType
	,LastPersScore as Score
	,COUNT(DISTINCT PathwayID) AS Count_Referrals
	,Month
	,[Provider Name]
	,[Region Name]
FROM [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]
GROUP BY LastPersScore
	,CodedAssToolType
	,Month
	,[Provider Name]
	,[Region Name]

--Drop temporary tables created to produce the final output tables
DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_CodedAssessReferral]
DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ7]
DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ8]
DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[TEMP_IAPT_PresenteeismQ9]