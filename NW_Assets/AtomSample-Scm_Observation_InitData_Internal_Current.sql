USE [NSLIJHS_Atom]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[usp_SCM_Observations_InitData_Internal_Current]
    @starttime DATETIME,
    @endtime DATETIME,
    @sessionid uniqueidentifier
AS

-- Offset Workaround for SCM Replication Delays
	set @starttime = dateadd(minute, -15, @starttime)
	set @endtime = dateadd(minute, -15, @endtime)

-- SET NOCOUNT ON added to prevent extra result sets from
-- interfering with SELECT statements.   
SET NOCOUNT ON;
              
DECLARE @isbackload BIT = 1
DECLARE @from_lsn binary(10) = NULL
DECLARE @to_lsn binary(10) = NULL
select @from_lsn = CDC.from_lsn, @to_lsn = CDC.to_lsn, @isbackload = CDC.isbackload, @endtime = CDC.endtime from [udf_GetCDCRange] ('CV3HealthIssueDeclaration_CDC', @starttime, @endtime) as CDC

-- select @starttime, @endtime, @isbackload, @from_lsn, @to_lsn, @min_lsn, @max_lsn, @min_time, @max_time

DECLARE @xmlresults xml = null

CREATE TABLE #OCMIGuid
(
	GUID numeric(16,0),
	ObsGUID numeric(16,0),
	ObsCodedValue nvarchar(250)
)

insert into
	#OCMIGuid
select
	OCMI.GUID,
	OCV.GUID,
	OCV.CodedValue
from 
	[dbo].[CV3OBSCATALOGMASTERITEMSYNONYM] AS OCMI With (Nolock) 
	INNER JOIN [dbo].[SCMOBSCODEDVALUESYNONYM] AS OCV With (Nolock) ON 
		OCV.ParentGUID = OCMI.GUID
		AND 
		OCV.CodingStandards in ('HSI_OBS')
		AND
		OCV.Active = 1

CREATE TABLE #OCMIGuidGroup
(
	GUID numeric(16,0),
	UnitOfMeasure nvarchar(30),
	ObservationLabel nvarchar(750),
	GroupName nvarchar(32)
)

;With CTE as
(
	SELECT 
		Distinct 
		OCMI.Name AS ObservationName,
		OCMI.Description AS ObservationDesc,
		CASE when ISNULL(rtrim(ltrim(ocmi.leftjustifiedlabel)), '') = ISNULL(rtrim(ltrim(ocmi.RightJustifiedLabel)), '') then ISNULL(rtrim(ltrim(ocmi.leftjustifiedlabel)), '') else RTRIM(LTRIM(ISNULL(rtrim(ltrim(ocmi.leftjustifiedlabel)), '') + ' ' + ISNULL(rtrim(ltrim(ocmi.rightjustifiedlabel)), ''))) END  As ObservationLabel,
		OCMI.UnitOfMeasure as UnitOfMeasure,
		CASE OCMI.DataType 
			WHEN 1 THEN 'Free Text'
			WHEN 2 THEN 'Numeric'
			WHEN 3 THEN 'Checkbox'
			WHEN 4 THEN 'Restricted Dictionary'
			WHEN 5 THEN 'Suggested Dictionary'
			WHEN 7 THEN 'User Defined Form'
			WHEN 8 THEN 'Date / Time'
			ELSE CONVERT(VARCHAR(50), OCMI.DataType)  
		END AS ObsValueDatatype,
		ocs.Description As CatologSetDescription,
		ocs.DisplayName As CatalogSetLabel, 
		OCMI.GUID AS ObsCatalogMasterItemGUID 
	FROM
		[dbo].[CV3FLOWSHEETVERSIONSYNONYM] AS fv With (Nolock) 
		INNER JOIN [dbo].[CV3PATIENTCAREDOCUMENTSYNONYM] AS pcd With (Nolock) on 
			pcd.KTreeRootGUID = fv.FlowsheetGUID
			Inner Join [dbo].[CV3DOCUMENTREVIEWCATEGORYSYNONYM] As Drc With (Nolock) On 
				Drc.Guid = Pcd.Docreviewcategoryguid
		Inner JOIN [dbo].[CV3OBSERVATIONENTRYITEMSYNONYM] AS OEI With (Nolock) ON 
			OEI.OwnerGUID = fv.FlowsheetGUID
			LEFT Join [dbo].[CV3OBSCATALOGSETSYNONYM] As ocs With (Nolock) On 
				ocs.guid = oei.ObsSetGUID
			Inner JOIN [dbo].[CV3OBSCATALOGMASTERITEMSYNONYM] AS OCMI With (Nolock) ON 
				OCMI.GUID = OEI.ObsMasterItemGUID
	where 
		fv.Active = 1
		AND 
		OCMI.Active = 1
		AND 
		OEI.Active = 1

)
insert into
	#OCMIGuidGroup
Select 
	Distinct 
	CTE.ObsCatalogMasterItemGUID,
	rtrim(ltrim(isnull(CTE.UnitOfMeasure, ''))),
	rtrim(ltrim(isnull(CTE.ObservationLabel, ''))),
	'Observation' As 'GroupName'

From 
	CTE OPTION (MAXDOP 4)

-- Improvement to only query CDC table once 
IF OBJECT_ID('tempdb..#CV3ObservationDocumentCUR_CDC', 'U') IS NOT NULL
DROP TABLE #CV3ObservationDocumentCUR_CDC
	SELECT
		ObservationDocumentGUID,
		__$start_lsn
		INTO #CV3ObservationDocumentCUR_CDC
	from 
		[PROD04].cdc.fn_cdc_get_net_changes_CV3ObservationDocumentCUR_CDC(@from_lsn, @to_lsn, 'all') OPTION (MAXDOP 4) 

CREATE CLUSTERED INDEX CI_CV3ObservationDocumentCUR_CDC ON #CV3ObservationDocumentCUR_CDC (ObservationDocumentGUID) WITH (MAXDOP = 4);


CREATE TABLE #ObservationData
(
	ClientVisitGUID NUMERIC(16,0),
	ClientIDCode VARCHAR(20),
	ClientDocumentGUID NUMERIC(16,0),
	ObservationDocumentGUID NUMERIC(16,0),
	CommitVersion DATETIME,
	LocationCode VARCHAR(160),
	ObsMasterItemGUID numeric(16, 0),
	CreatedWhen datetime,
	ObsCodedValue nvarchar(250),
	ObservationValue nvarchar(max)
)

insert into
	#ObservationData
select
	CV.GUID as ClientVisitGUID,
	CI.ClientIDCode as ClientIDCode,
	CD.GUID as ClientDocumentGUID,
	OD.ObservationDocumentGUID as ObservationDocumentGUID,
	isnull([PROD04].sys.fn_cdc_map_lsn_to_time(CT.__$start_lsn), @starttime) as CommitVersion,
	rtrim(LEFT(L.Code, 15)) as LocationCode,
	OD.ObsMasterItemGUID as ObsMasterItemGUID,
	OD.CreatedWhen as CreatedWhen,
	OCMI.ObsCodedValue as ObsCodedValue,
	[dbo].[udf_GetObservationValue](OD.ObservationGUID, OD.ObservationDocumentGUID, CD.ClientGUID) as ObservationValue
From
	(
		SELECT
			ObservationDocumentGuid,
			__$start_lsn
		from 
			#CV3ObservationDocumentCUR_CDC
	) CT
	INNER JOIN [CV3OBSERVATIONDOCUMENTCURSYNONYM] OD WITH(NOLOCK) ON
		OD.ObservationDocumentGUID = CT.ObservationDocumentGuid
		INNER JOIN #OCMIGuid AS OCMI WITH (NOLOCK) ON
			OCMI.GUID = OD.ObsMasterItemGUID
		inner join [dbo].[CV3CLIENTDOCUMENTSYNONYM] CD WITH(NOLOCK) on
			CD.GUID = OD.OwnerGUID
			INNER JOIN [CV3CLIENTVISITSYNONYM] CV  WITH(NOLOCK) ON
				CV.ClientGUID = CD.ClientGUID
				AND
				CV.GUID = CD.ClientVisitGUID
				INNER JOIN [dbo].[CV3LOCATIONSYNONYM] L WITH (NOLOCK) ON 
					L.GUID = CV.CurrentLocationGUID
				INNER JOIN [dbo].[CV3CLIENTIDSYNONYM] CI WITH (NOLOCK) ON 
					CI.ClientGUID = CV.ClientGUID
					AND
					CI.TypeCode ='EPI' 
					AND 
					CI.Active = '1' 
					AND 
					CI.IDStatus = 'ACT'
where
	OD.Active = 0
	AND CV.CareLevelCode NOT IN ('.Downtime')
union
select
	X.ClientVisitGUID as ClientVisitGUID,
	X.ClientIDCode as ClientIDCode,
	X.ClientDocumentGUID as ClientDocumentGUID,
	X.ObservationDocumentGUID as ObservationDocumentGUID,
	X.SYS_CHANGE_VERSION as CommitVersion,
	X.LocationCode as LocationCode,
	X.ObsMasterItemGUID as ObsMasterItemGUID,
	X.CreatedWhen as CreatedWhen,
	X.ObsCodedValue as ObsCodedValue,
	X.ValueText as ObservationValue
from
(
	select
		CV.GUID as ClientVisitGUID,
		CI.ClientIDCode as ClientIDCode,
		CD.GUID as ClientDocumentGUID,
		OD.ObservationDocumentGUID as ObservationDocumentGUID,
		isnull([PROD04].sys.fn_cdc_map_lsn_to_time(CT.__$start_lsn), @starttime) as SYS_CHANGE_VERSION,
		rtrim(LEFT(L.Code, 15)) as LocationCode,
		OD.ObsMasterItemGUID as ObsMasterItemGUID,
		OD.CreatedWhen as CreatedWhen,
		OCMI.ObsCodedValue as ObsCodedValue,
		[dbo].[udf_GetObservationValue](OD.ObservationGUID, OD.ObservationDocumentGUID, CD.ClientGUID) as ValueText,
		ROW_NUMBER() over (partition by CV.GUID, OD.ObsMasterItemGUID, OD.RecordedDtm, [dbo].[udf_GetObservationValue](OD.ObservationGUID, OD.ObservationDocumentGUID, CD.ClientGUID) order by OD.CreatedWhen asc) as RankId
	From
		(
			SELECT
				ObservationDocumentGuid,
				__$start_lsn
			from 
				#CV3ObservationDocumentCUR_CDC
		) CT
		JOIN [CV3OBSERVATIONDOCUMENTCURSYNONYM] OD WITH(NOLOCK) ON
			OD.ObservationDocumentGUID = CT.ObservationDocumentGuid
			INNER JOIN #OCMIGuid AS OCMI WITH (NOLOCK) ON
				OCMI.GUID = OD.ObsMasterItemGUID
			inner join [dbo].[CV3CLIENTDOCUMENTSYNONYM] CD WITH(NOLOCK) on
				CD.GUID = OD.OwnerGUID
				INNER JOIN [CV3CLIENTVISITSYNONYM] CV  WITH(NOLOCK) ON
					CV.ClientGUID = CD.ClientGUID
					AND
					CV.GUID = CD.ClientVisitGUID
					INNER JOIN [dbo].[CV3LOCATIONSYNONYM] L WITH (NOLOCK)  ON 
						L.GUID = CV.CurrentLocationGUID
					INNER JOIN [dbo].[CV3CLIENTIDSYNONYM] CI WITH (NOLOCK) ON 
						CI.ClientGUID = CV.ClientGUID
						AND
						CI.TypeCode ='EPI' 
						AND 
						CI.Active = '1' 
						AND 
						CI.IDStatus = 'ACT'
	where
		OD.Active = 1
		AND CV.CareLevelCode NOT IN ('.Downtime')
) X
where
	X.RankId = 1


CREATE TABLE #DistinctEncounters
(
	ClientVisitGUID NUMERIC(16,0),
	ClientIDCode VARCHAR(20),
	LocationCode VARCHAR(160),
	CommitVersion DATETIME
)

insert into
	#DistinctEncounters
select
	ClientVisitGUID,
	ClientIDCode,
	max(LocationCode),
	max(CommitVersion)
from
	#ObservationData
group by
	ClientVisitGUID,
	ClientIDCode
	
BEGIN TRY
	set @xmlresults =
	(
		SELECT
			@endtime AS 'ReferenceId',
			DE.LocationCode as 'SendingFacility',
			(
				select 
					X.*
				from
				(
					select
						DE.LocationCode as 'Organization/Code',
						rtrim(ltrim(CV.IDCode))  as 'Number',
						'MRN' as 'NumberType'
					union
					select
						'EPI' as 'Organization/Code',
						DE.ClientIDCode as 'Number',
						'XX' as 'NumberType'
				) X
				for
					XML PATH('PatientNumber'),
					TYPE 
			) as 'Patient/PatientNumbers',
			(
				select
					rtrim(ltrim(CV.TypeCode)) as 'EncounterType',
					rtrim(ltrim(CV.VisitIDCode)) as 'EncounterNumber',
					isnull(convert(varchar(30), CV.AdmitDTM, 120), '') AS 'FromTime',
          isnull(convert(varchar(30), isnull(CV.DischargeDTM, CV.CloseDTM), 120), '') AS 'ToTime'
				for
					XML PATH('Encounter'),
					TYPE
			) as 'Encounters',
			(
				select
					ODATA.ObsCodedValue as 'HSICode',
					rtrim(ltrim(CV.VisitIDCode)) as 'EncounterNumber',
					CD.PatCareDocGUID as 'GroupId',
					convert(varchar(30), OD.RecordedDtm, 120) as 'RecordedDtm',
					convert(varchar(30), CD.TouchedWhen, 120) as 'TouchedWhen',
					[dbo].[udf_GetObservationValue](OD.ObservationGUID, OD.ObservationDocumentGUID, CD.ClientGUID) as 'ObservationValue',
					case 
						when OD.Active = 1 And ODATA.ObservationValue = '' then 0
						else OD.Active
					end as 'ActionCode',
					[dbo].[udf_ConcatenateClientDocumentComments](CD.GUID) as 'Comments',
					DE.LocationCode as 'LocationCode',
					OCMI.ObservationLabel as 'ObservationLabel',
					OCMI.UnitOfMeasure as 'UnitOfMeasure',
					OD.ObservationDocumentGUID as 'ObservationDocumentGUID',
					OD.OriginalObsGUID as 'OriginalObsGUID',
					U.FirstName as 'GivenName',
					U.LastName as 'FamilyName',
					U.OccupationCode as 'ProfessionalSuffix',
					U.IDCode as 'UserIDCode',
					U.OrderRoleType as 'OrderRoleType',
					CD.DocumentName as 'DocumentName',
					PCD.Name as 'PatCareDocumentName'
				from
					#ObservationData ODATA
					INNER JOIN [CV3OBSERVATIONDOCUMENTCURSYNONYM] OD WITH(NOLOCK) ON
						OD.ObservationDocumentGUID = ODATA.ObservationDocumentGUID
						INNER JOIN [CV3CLIENTDOCUMENTSYNONYM] CD WITH(NOLOCK) ON
							CD.GUID = OD.OwnerGUID
							LEFT JOIN [dbo].[CV3PATIENTCAREDOCUMENTSYNONYM] AS PCD With (Nolock) ON
								PCD.[GUID] = CD.[PatCareDocGUID]
						INNER JOIN #OCMIGuidGroup AS OCMI WITH (NOLOCK) ON
							OCMI.Guid = OD.ObsMasterItemGUID
						Left Join [CV3OBSERVATIONCURSYNONYM] As O With (Nolock) On 
							O.Guid = OD.Observationguid
							Left Join  [CV3USERSYNONYM] AS U With (Nolock) On 
								U.GUID = O.UserGuid
				where
					ODATA.ClientVisitGUID = DE.ClientVisitGUID
				order by
					OD.ObservationDocumentGUID asc
				for
					XML PATH('Observation'),
					TYPE
			) as 'Observations'
		From
			#DistinctEncounters DE
			INNER JOIN [CV3CLIENTVISITSYNONYM] CV WITH(NOLOCK) ON
				CV.GUID = DE.ClientVisitGUID
		ORDER BY
			CV.VisitIDCode
		FOR XML
			PATH('Container'),
			ROOT('SCMObservations'),
			BINARY BASE64
	)
			
END TRY

BEGIN CATCH
	DECLARE @ErrorMessage NVARCHAR(4000)
	DECLARE @ErrorSeverity INT
	DECLARE @ErrorState INT

	SELECT  @ErrorMessage = OBJECT_NAME(@@PROCID) + '(' + CAST(ERROR_LINE() AS VARCHAR(50)) + '): ' + ERROR_MESSAGE(),
			@ErrorSeverity = ERROR_SEVERITY(),
			@ErrorState = ERROR_STATE()

	RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)
END CATCH

if @xmlresults is not null
begin
    if @sessionid is not null
    begin
        declare @rowmax bigint
        select @rowmax = isnull(max(pk1), 0) from TInitData where GUID = @sessionid
        SELECT
            @sessionid,
            @rowmax + ROW_NUMBER() over (order by c), 
            @rowmax + ROW_NUMBER() over (order by c), 
            T.c.query('.')
        FROM
            @xmlresults.nodes('/SCMObservations/Container') T(c)
    end
    else
    begin
        select @xmlresults
    end
end

DROP TABLE #DistinctEncounters
DROP TABLE #ObservationData
DROP TABLE #OCMIGuidGroup
DROP TABLE #OCMIGuid
DROP TABLE #CV3ObservationDocumentCUR_CDC