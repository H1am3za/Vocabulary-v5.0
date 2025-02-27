/**************************************************************************
* Copyright 2016 Observational Health Data Sciences AND Informatics (OHDSI)
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
* 
* Authors: Timur Vakhitov, Christian Reich, Anna Ostropolets, Dmitry Dymshyts, Alexander Davydov
* Date: 2020
**************************************************************************/

--1. UPDATE latest_UPDATE field to new date 
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.SetLatestUpdate(
	pVocabularyName			=> 'HCPCS',
	pVocabularyDate			=> (SELECT vocabulary_date FROM sources.anweb_v2 LIMIT 1),
	pVocabularyVersion		=> (SELECT vocabulary_version FROM sources.anweb_v2 LIMIT 1),
	pVocabularyDevSchema	=> 'DEV_HCPCS'
);
END $_$;

-- 2. Truncate all working tables
TRUNCATE TABLE concept_stage;
TRUNCATE TABLE concept_relationship_stage;
TRUNCATE TABLE concept_synonym_stage;
TRUNCATE TABLE pack_content_stage;
TRUNCATE TABLE drug_strength_stage;

--3. Create concept_stage from HCPCS
INSERT INTO concept_stage (
	concept_name,
	domain_id,
	vocabulary_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT vocabulary_pack.CutConceptName(long_description) AS concept_name,
	c.domain_id AS domain_id,
	v.vocabulary_id,
	CASE 
		WHEN LENGTH(hcpc) = 2
			THEN 'HCPCS Modifier'
		ELSE 'HCPCS'
		END AS concept_class_id,
	CASE 
		WHEN term_dt IS NOT NULL
			AND xref1 IS NOT NULL -- !!means the concept is updated
			THEN NULL
		ELSE 'S' -- in other cases it's standard because of the new deprecation logic
		END AS standard_concept,
	HCPC AS concept_code,
	COALESCE(add_date, act_eff_dt) AS valid_start_date,
	COALESCE(term_dt, TO_DATE('20991231', 'yyyymmdd')) AS valid_end_date,
	CASE 
		WHEN term_dt IS NULL
			THEN NULL
		WHEN xref1 IS NULL
			THEN NULL -- deprecated, but leave alive
		ELSE 'U' -- upgraded
		END AS invalid_reason
FROM sources.anweb_v2 a
JOIN vocabulary v ON v.vocabulary_id = 'HCPCS'
LEFT JOIN concept c ON c.concept_code = a.betos
	AND c.concept_class_id = 'HCPCS Class'
	AND c.vocabulary_id = 'HCPCS';


--4 UPDATE domain_id in concept_stage
--4.1. Part 1. UPDATE domain_id defined by rules
WITH t_domains
AS (
	SELECT hcpc.concept_code,
		CASE
			WHEN concept_name LIKE '%per session%'
				THEN 'Procedure'
					-- A codes
			WHEN concept_code IN (
					'A4248',
					'A9527',
					'A9517',
					'A9530',
					'A4802',
					'A9543',
					'A9545',
					'A9563',
					'A9564',
					'A9600',
					'A9604',
					'A9605',
					'A9606'
					)
				THEN 'Drug'
			WHEN l1.str = 'A Codes'
				AND concept_code NOT IN (
					'A4736',
					'A4737',
					'A9527',
					'A9517',
					'A9530',
					'A9606',
					'A9543',
					'A9563',
					'A9564',
					'A9600',
					'A9604',
					'A4248',
					'A4802',
					'A9152',
					'A9153',
					'A9180',
					'A9155'
					)
				AND l2.str <> 'Transport Services Including Ambulance'
				THEN 'Device' -- default for Level 1: A0000-A9999
			WHEN l2.str = 'Transport Services Including Ambulance'
				THEN 'Observation' -- Level 2: A0000-A0999
			WHEN concept_code IN (
					'A4736',
					'A4737',
					'A9180'
					)
				THEN 'Procedure'
			WHEN concept_code IN (
					'A9152',
					'A9153'
					)
				THEN 'Drug' --Vitamin preparations
			WHEN concept_code = 'A9155'
				THEN 'Device' --Artificial saliva, 30 ml
					-- B codes
			WHEN l2.str = 'Enteral and Parenteral Therapy Supplies'
				THEN 'Device' -- all of them Level 1: B4000-B9999
					-- C codes
			WHEN concept_code = 'C1204'
				THEN 'Device' -- Technetium tc 99m tilmanocept, diagnostic, up to 0.5 millicuries
			WHEN concept_code IN (
					'C1178',
					'C9003'
					)
				THEN 'Drug' -- cancer drug
			WHEN concept_code LIKE 'C%'
				AND concept_name LIKE '%Brachytherapy%source%'
				THEN 'Device' -- Brachytherapy codes
			WHEN concept_code LIKE 'C%'
				AND concept_name LIKE '%Magnetic resonance% with%'
				THEN 'Procedure' -- MRIs
			WHEN concept_code LIKE 'C%'
				AND concept_name LIKE '%Trans% echocardiography%'
				THEN 'Procedure' -- Echocardiography
			WHEN concept_code IN (
					'C8953',
					'C8954',
					'C8955'
					)
				THEN 'Procedure'
			WHEN concept_code IN (
					'C9000',
					'C9007',
					'C9008',
					'C9009',
					'C9013'
					)
				THEN 'Drug'
			WHEN concept_code IN (
					'C9060',
					'C9067',
					'C9068',
					'C9200',
					'C9201',
					'C9123',
					'C9102'
					)
				THEN 'Device'
			WHEN concept_code IN (
					'C9246',
					'C9247',
					'C9221',
					'C9222'
					) -- Contrast agent's
				THEN 'Device'
			WHEN concept_code BETWEEN 'C9021'
					AND 'C9348'
				THEN 'Drug' -- various drug products
			WHEN concept_code = 'C9349'
				THEN 'Device'
			WHEN concept_code BETWEEN 'C9352'
					AND 'C9369'
				THEN 'Device' -- various graft matrix material
			WHEN concept_code IN (
					'C9406',
					'C9407'
					)
				THEN 'Device' -- Iodine i-123 ioflupane, diagnostic, per study dose, up to 5 millicuries
			WHEN concept_code = 'C9399'
				THEN 'Drug' -- Unclassified drugs or biologicals
			WHEN concept_code BETWEEN 'C9408'
					AND 'C9497'
				THEN 'Drug'
			WHEN concept_code BETWEEN 'C9600'
					AND 'C9800'
				THEN 'Procedure'
			WHEN l1.str = 'C Codes - CMS Hospital Outpatient System'
				THEN 'Device' -- default for Level 1: C1000-C9999
					-- D codes
			WHEN concept_code IN (
					'D5860',
					'D5861',
					'D6970',
					'D6971',
					'D6972',
					'D6973',
					'D0260',
					'D0290',
					'D2970',
					'D6053',
					'D6054',
					'D6078',
					'D6079',
					'D6975'
					)
				THEN 'Device' -- D-codes device
			WHEN concept_code BETWEEN 'D0260'
					AND 'D9242'
				THEN 'Procedure' -- D-code prcedures
					-- E codes
			WHEN l1.str = 'E-codes'
				THEN 'Device' -- all of them Level 1: E0100-E9999
					-- G codes
			WHEN l2.str = 'Vaccine Administration' -- hard to say why it was Procedure but not a drug?
				THEN 'Drug' -- Level 2: G0008-G0010
			WHEN concept_code = 'G0027'
				THEN 'Measurement' -- Level 2: G0027-G0027
			WHEN concept_code IN (
					'G0048',
					'G0049',
					'G0050',
					'G0051',
					'G0052',
					'G0053',
					'G0054',
					'G0055',
					'G0056',
					'G0057',
					'G0058',
					'G0058',
					'G0059',
					'G0060',
					'G0061',
					'G0062',
					'G0063',
					'G0064',
					'G0065',
					'G0066',
					'G0067'
					)
				THEN 'Observation' -- codes added in 2022, MIPS specialty sets for particular medical specialties
			WHEN concept_code IN (
					'G0101',
					'G0102'
					)
				THEN 'Procedure'
			WHEN concept_code = 'G0103'
				THEN 'Measurement' -- Prostate cancer screening; prostate specific antigen test (psa)
			WHEN l2.str = 'Diabetes Management Training Services'
				THEN 'Observation' -- Level 2: G0108-G0109
			WHEN concept_code BETWEEN 'G0123'
					AND 'G0124'
				THEN 'Measurement' -- G0123-G0124 Screening cytopathology
			WHEN concept_code BETWEEN 'G0128'
					AND 'G0129'
				THEN 'Observation' -- Level 2: G0128-G0129 previously 'Service, Nurse AND OT'
			WHEN concept_code BETWEEN 'G0141'
					AND 'G0148'
				THEN 'Measurement' -- G0141-G0148 Screening cytopathology
			WHEN concept_code BETWEEN 'G0151'
					AND 'G0166'
				THEN 'Observation' -- Level 2: G0151-G0166 previously 'Services, Allied Health'
			WHEN concept_code = 'G0175'
				THEN 'Observation' -- Level 2: G0175-G0175 previously 'Team Conference'
			WHEN concept_code BETWEEN 'G0179'
					AND 'G0182'
				THEN 'Observation' -- Level 2: G0179-G0182 previously 'Physician Services'
			WHEN concept_code BETWEEN 'G0237'
					AND 'G0239'
				THEN 'Procedure' -- Level 2: G0237-G0239 previously 'Therapeutic Procedures'
			WHEN concept_code BETWEEN 'G0245'
					AND 'G0246'
				THEN 'Observation' -- Level 2: G0245-G0246  'Physician Services, Diabetic'
			WHEN concept_code BETWEEN 'G0248'
					AND 'G0250'
				THEN 'Observation' -- Level 2: G0248-G0250 previously 'Demonstration, INR'
			WHEN concept_code = 'G3001'
				THEN 'Drug' -- Level 2: G3001-G3001 previously 'Tositumomab'
			WHEN concept_code BETWEEN 'G0302'
					AND 'G0305'
				THEN 'Observation' -- Level 2: G0302-G0305 previously 'Services, Pulmonary Surgery'
			WHEN concept_code IN (
					'G0306',
					'G0307',
					'G0328'
					)
				THEN 'Measurement'
			WHEN concept_code BETWEEN 'G0308'
					AND 'G0327'
				THEN 'Observation' -- ESRD services
			WHEN concept_code = 'G0333'
				THEN 'Procedure' -- Level 2: G0333-G0333 previously 'Fee, Pharmacy'
			WHEN concept_code = 'G0337'
				THEN 'Observation' -- Level 2: G0337-G0337 previously 'Hospice'
			WHEN l2.str = 'Hospital Services: Observation and Emergency Department'
				THEN 'Observation' -- Level 2: G0378-G0384
			WHEN l2.str = 'Trauma Response Team'
				THEN 'Observation' -- Level 2: G0390-G0390
			WHEN l2.str = 'Home Sleep Study Test'
				THEN 'Procedure' --G0398-G0400
			WHEN l2.str = 'Initial Examination for Medicare Enrollment'
				THEN 'Observation' -- Level 2: G0402-G0402
			WHEN l2.str = 'Electrocardiogram'
				THEN 'Procedure' -- Level 2: G0403-G0405 -- changed to procedure because there could be various results
			WHEN l2.str = 'Follow-up Telehealth Consultation'
				THEN 'Observation' -- Level 2: G0406-G0408
			WHEN l2.str = 'Psychological Services'
				THEN 'Observation' -- Level 2: G0409-G0411
			WHEN concept_code BETWEEN 'G0416'
					AND 'G0419'
				THEN 'Procedure' -- Level 2: G0416-G0419 previously 'Pathology, Surgical'
			WHEN concept_code = 'G0424'
				THEN 'Procedure'
			WHEN concept_code IN (
					'G0428',
					'G0429'
					)
				THEN 'Procedure'
			WHEN concept_code BETWEEN 'G0430'
					AND 'G0435'
				THEN 'Measurement' -- drug screen, infectious antibodies
			WHEN concept_code IN (
					'G0438',
					'G0439'
					)
				THEN 'Observation' -- annual wellness visit
			WHEN concept_code IN (
					'G0440',
					'G0441'
					)
				THEN 'Procedure' -- allogenic skin substitute
			WHEN concept_code IN (
					'G0442',
					'G0443',
					'G0444',
					'G0445',
					'G0446',
					'G0447'
					)
				THEN 'Procedure' -- Various screens AND counseling
			WHEN concept_code = 'G0448'
				THEN 'Procedure' -- Insertion or replacement of a permanent pacing cardioverter-defibrillator system with transvenous lead(s), single or dual chamber with insertion of pacing electrode, cardiac venous system, for left ventricular pacing
			WHEN concept_code = 'G0451'
				THEN 'Observation' -- Development testing, with interpretation AND report, per standardized instrument form
			WHEN concept_code = 'G0452'
				THEN 'Measurement' -- Molecular pathology procedure; physician interpretation AND report
			WHEN concept_code = 'G0453'
				THEN 'Procedure' -- Continuous intraoperative neurophysiology monitoring, from outside the operating room (remote or nearby), per patient, (attention directed exclusively to one patient) each 15 minutes (list in addition to primary procedure)
			WHEN concept_code = 'G0454'
				THEN 'Observation' -- Physician documentation of face-to-face visit for durable medical equipment determination performed by nurse practitioner, physician assistant or clinical nurse specialist
			WHEN concept_code = 'G0455'
				THEN 'Procedure' -- Preparation with instillation of fecal microbiota by any method, including assessment of donor specimen
			WHEN concept_code IN (
					'G0456',
					'G0457'
					)
				THEN 'Procedure' -- Negative pressure wound therapies
			WHEN concept_code = 'G0458'
				THEN 'Procedure' -- Low dose rate (ldr) prostate brachytherapy services, composite rate
			WHEN concept_code = 'G0459'
				THEN 'Procedure' -- Inpatient telehealth pharmacologic management, including prescription, use, AND review of medication with no more than minimal medical psychotherapy
			WHEN concept_code = 'G0460'
				THEN 'Procedure' -- Autologous platelet rich plasma for chronic wounds/ulcers, incuding phlebotomy, centrifugation, AND all other preparatory procedures, administration AND dressings, per treatment
			WHEN concept_code IN (
					'G0461',
					'G0462'
					)
				THEN 'Measurement' -- Immunohistochemistry or immunocytochemistry
			WHEN concept_code = 'G0463'
				THEN 'Observation' -- Hospital outpatient clinic visit for assessment AND management of a patient
			WHEN concept_code = 'G0464'
				THEN 'Measurement' -- Colorectal cancer screening; stool-based dna AND fecal occult hemoglobin (e.g., kras, ndrg4 AND bmp3)
			WHEN concept_code IN (
					'G0466',
					'G0467',
					'G0468',
					'G0469',
					'G0470'
					)
				THEN 'Observation' -- Federally qualified health center (fqhc) visits
			WHEN concept_code = 'G0471'
				THEN 'Procedure' -- Collection of venous blood by venipuncture or urine sample by catheterization from an individual in a skilled nursing facility (snf) or by a laboratory on behalf of a home health agency (hha)
			WHEN concept_code = 'G0472'
				THEN 'Measurement' -- Hepatitis c antibody screening, for individual at high risk AND other covered indication(s)
			WHEN concept_code = 'G0473'
				THEN 'Procedure' -- Face-to-face behavioral counseling for obesity, group (2-10), 30 minutes
			WHEN concept_code IN (
					'G0908',
					'G0909',
					'G0910',
					'G0911',
					'G0912',
					'G0913',
					'G0914',
					'G0915',
					'G0916',
					'G0917',
					'G0918',
					'G0919',
					'G0920',
					'G0921',
					'G0922',
					'G2184'
					)
				THEN 'Observation' -- various documented levels AND assessments
			WHEN concept_code = 'G3001'
				THEN 'Drug' -- Administration and supply of tositumomab, 450 mg
			WHEN concept_code IN (
					'G4000',
					'G4001',
					'G4002',
					'G4003',
					'G4004',
					'G4005',
					'G4006',
					'G4007',
					'G4008',
					'G4009',
					'G4010',
					'G4011',
					'G4012',
					'G4013',
					'G4014',
					'G4015',
					'G4016',
					'G4017',
					'G4018',
					'G4019',
					'G4020',
					'G4021',
					'G4022',
					'G4023',
					'G4024',
					'G4025',
					'G4026',
					'G4027',
					'G4028',
					'G4029',
					'G4030',
					'G4031',
					'G4032',
					'G4033',
					'G4034',
					'G4035',
					'G4036',
					'G4037',
					'G4038'
					)
				THEN 'Observation' -- codes added in 2022, MIPS specialty sets for particular medical specialties
			WHEN concept_code IN (
					'G6001',
					'G6002',
					'G6003',
					'G6004',
					'G6005',
					'G6006',
					'G6007',
					'G6008',
					'G6009',
					'G6010',
					'G6011',
					'G6012',
					'G6013',
					'G6014',
					'G6015',
					'G6016',
					'G6017'
					)
				THEN 'Procedure' -- various radiation treatment deliveries
			WHEN concept_code IN (
					'G6018',
					'G6019',
					'G6020',
					'G6021',
					'G6022',
					'G6023',
					'G6024',
					'G6025',
					'G6027',
					'G6028'
					)
				THEN 'Procedure' -- various ileo/colono/anoscopies
			WHEN concept_code BETWEEN 'G6030'
					AND 'G6058'
				THEN 'Measurement' -- drug screening
					-- Level 2: G8126-G9140, mostly Physician Quality Reporting System (PQRS)
			WHEN concept_code BETWEEN 'G8006'
					AND 'G8117'
				THEN 'Observation' -- aren't present in UMLS
			WHEN concept_code BETWEEN 'G8126'
					AND 'G8394'
				THEN 'Observation' -- outdated concepts, aren't present in UMLS, so hardcode them
			WHEN concept_code BETWEEN 'G8977'
					AND 'G9012'
				THEN 'Observation' --Functional Limitation, Coordinated Care
			WHEN concept_code IN (
					'G9752',
					'G9756',
					'G9757',
					'G9643'
					)
				THEN 'Procedure' -- Emergency surgery, Elective surgery, Surgical procedures that included the use of silicone oil
			WHEN concept_code IN (
					'G9641',
					'G9639',
					'G9654',
					'G9770',
					'G9937',
					'G9839'
					)
				THEN 'Procedure'
			WHEN concept_code IN (
					'G9141',
					'G9142',
					'G9017',
					'G9018',
					'G9019',
					'G9020',
					'G9033',
					'G9034',
					'G9035',
					'G9036'
					)
				THEN 'Drug' -- Influenza a (h1n1) immunization administration + other drugs
			WHEN concept_code = 'G9143'
				THEN 'Measurement' -- Warfarin responsiveness testing by genetic technique using any method, any number of specimen(s)
			WHEN concept_code = 'G9147'
				THEN 'Procedure' -- Outpatient intravenous insulin treatment (oivit) either pulsatile or continuous, by any means, guided by the results of measurements for: respiratory quotient; and/or, urine urea nitrogen (uun); and/or, arterial, venous or capillary glucose; and/or potassi
			WHEN concept_code IN (
					'G9148',
					'G9149',
					'G9150'
					)
				THEN 'Observation' -- National committee for quality assurance - medical home levels
			WHEN concept_code IN (
					'G9151',
					'G9152',
					'G9153'
					)
				THEN 'Observation' -- Multi-payer Advanced Primary Care Practice (MAPCP) Demonstration Project
			WHEN concept_code = 'G9156'
				THEN 'Procedure' -- Evaluation for wheelchair requiring face to face visit with physician
			WHEN concept_code = 'G9157'
				THEN 'Procedure' -- Transesophageal doppler measurement of cardiac output (including probe placement, image acquisition, AND interpretation per course of treatment) for monitoring purposes
			WHEN concept_code BETWEEN 'G9158'
					AND 'G9186'
				THEN 'Observation' -- various neurological functional limitations documentations
			WHEN concept_code = 'G9187'
				THEN 'Observation' -- Bundled payments for care improvement initiative home visit for patient assessment performed by a qualified health care professional for individuals not considered homebound including, but not limited to, assessment of safety, falls, clinical status, fluid
			WHEN concept_code BETWEEN 'G9188'
					AND 'G9472'
				THEN 'Observation' -- various documentations
			WHEN concept_code BETWEEN 'G9473'
					AND 'G9479'
				THEN 'Observation'
			WHEN concept_code BETWEEN 'G9679'
					AND 'G9684'
				THEN 'Observation'
			WHEN concept_code BETWEEN 'G9514'
					AND 'G9517'
				THEN 'Observation'
			WHEN concept_code IN (
					'G0238',
					'G0293',
					'G0294',
					'G0403',
					'G0404',
					'G0405',
					'G0445',
					'G0453',
					'G9771',
					'G9773',
					'G9812',
					'G9601',
					'G9602'
					)
				THEN 'Observation'
					--	WHEN concept_code = 'G9642' -- seems to be Observation, hard to say why they put this here
					--	THEN 'Observation'
			WHEN l2.str IN (
					'Quality Measures: Miscellaneous',
					'Quality Measures',
					'Demonstration Project'
					)
				THEN 'Observation'
			WHEN concept_code BETWEEN 'G9000'
					AND 'G9140'
				THEN 'Procedure' -- default for Medicare Demonstration Project
			WHEN l1.str = 'Temporary Procedures/Professional Services'
				THEN 'Procedure' -- default for all Level 1: G0000-G9999
					-- H codes
			WHEN concept_code = 'H0003'
				THEN 'Measurement' -- Alcohol and/or drug screening; laboratory analysis of specimens for presence of alcohol and/or drugs
			WHEN concept_code = 'H0030'
				THEN 'Observation' -- Behavioral health hotline service
			WHEN concept_code = 'H0033'
				THEN 'Procedure' -- Oral medication administration, direct observation
			WHEN concept_code IN (
					'H0048',
					'H0049'
					)
				THEN 'Measurement' -- Alcohol screening
			WHEN concept_code BETWEEN 'H0034'
					AND 'H2037'
				THEN 'Observation' -- various services
			WHEN l1.str = 'Behavioral Health and/or Substance Abuse Treatment Services'
				THEN 'Procedure' -- default for all Level 1: H0001-H9999
					-- J codes
			WHEN concept_code = 'J7341'
				THEN 'Device'
			WHEN concept_code BETWEEN 'J7343'
					AND 'J7350'
				THEN 'Device'
			WHEN l1.str = 'J Codes - Drugs'
				THEN 'Drug' -- Level 1: J0100-J9999
					-- K codes
			WHEN l1.str = 'Temporary Codes Assigned to Durable Medical Equipment Regional Carriers'
				THEN 'Device' -- Level 1: K0000-K9999
			WHEN concept_code IN ('K1006',
					'K1007',
					'K1009',
					'K1010',
					'K1011',
					'K1012',
					'K1013',
					'K1014',
					'K1015',
					'K1016',
					'K1017',
					'K1018',
					'K1019',
					'K1020',
					'K1021',
					'K1022',
					'K1023',
					'K1024',
					'K1025',
					'K1026',
					'K1027',
					'K1028',
					'K1029',
					'K1030',
					'K1031',
					'K1032',
					'K1033',
					'K1034'
					)
				THEN 'Device'
					-- L codes
			WHEN l1.str = 'L Codes'
				THEN 'Device' -- Level 1: L0000-L9999
					-- M codes
			WHEN concept_code IN (
					'M0075', --Cellular therapy
					'M0076', --Prolotherapy
					'M0100', --Intragastric hypothermia using gastric freezing
					'M0300', --Iv chelation therapy (chemical endarterectomy)
					'M0301' --Fabric wrapping of abdominal aneurysm
					)
				THEN 'Procedure'
			WHEN l1.str = 'Other Medical Services'
				THEN 'Observation' -- Level 1: M0000-M0301
					-- P codes
			WHEN concept_code = 'P9012'
				THEN 'Drug' -- Cryoprecipitate, each unit should have domain_id = 'Drug'
			WHEN concept_code LIKE 'P90%'
				AND concept_code NOT BETWEEN 'P9041'
					AND 'P9048'
				THEN 'Device' -- All other P90% - blood components (AVOF-707)
			WHEN l2.str = 'Chemistry and Toxicology Tests'
				THEN 'Measurement' -- Level 2: P2028-P2038
			WHEN l2.str = 'Pathology Screening Tests'
				THEN 'Measurement' -- Level 2: P3000-P3001
			WHEN l2.str = 'Microbiology Tests'
				THEN 'Measurement' -- Level 2: P7001-P7001
			WHEN concept_code BETWEEN 'P9041'
					AND 'P9048'
				THEN 'Drug'
			WHEN l2.str = 'Miscellaneous Pathology and Laboratory Services'
				THEN 'Procedure' -- Level 2: P9010-P9100
			WHEN l2.str = 'Catheterization for Specimen Collection'
				THEN 'Procedure' -- Level 2: P9612-P9615
					-- Q codes
			WHEN concept_code IN (
					'Q0136',
					'Q0137',
					'Q0187',
					'Q2001',
					'Q2002',
					'Q2003',
					'Q4054',
					'Q4055'
					)
				THEN 'Drug'
			WHEN concept_code BETWEEN 'Q9941'
					AND 'Q9944'
				THEN 'Drug'
			WHEN concept_code IN (
					'Q1001',
					'Q1002'
					)
				THEN 'Device'
			WHEN l2.str = 'Cardiokymography (CMS Temporary Codes)'
				THEN 'Procedure' -- Level 2: Q0035-Q0035
			WHEN l2.str = 'Chemotherapy (CMS Temporary Codes)'
				OR concept_code BETWEEN 'Q0081'
					AND 'Q0085'
				THEN 'Procedure' -- Level 2: Q0081-Q0085
			WHEN concept_code = 'Q0090'
				THEN 'Device' -- Levonorgestrel-releasing intrauterine contraceptive system, (skyla), 13.5 mg
			WHEN l2.str = 'Smear, Papanicolaou (CMS Temporary Codes)'
				THEN 'Procedure' -- Level 2: Q0091-Q0091, only getting the smear, no interpretation
			WHEN l2.str = 'Equipment, X-Ray, Portable (CMS Temporary Codes)'
				THEN 'Observation' -- Level 2: Q0092-Q0092, only setup
			WHEN l2.str = 'Laboratory (CMS Temporary Codes)'
				THEN 'Measurement' -- Level 2: Q0111-Q0115
			WHEN l2.str = 'Drugs (CMS Temporary Codes)'
				THEN 'Drug' -- Level 2: Q0138-Q0181
			WHEN concept_code IN (
					'Q0182',
					'Q0183'
					)
				THEN 'Device'
			WHEN l2.str = 'Ventricular Assist Devices (CMS Temporary Codes)'
				THEN 'Device' -- Level 2: Q0477-Q0509
			WHEN l2.str = 'Fee, Pharmacy (CMS Temporary Codes)'
				AND concept_code != 'Q0515'
				THEN 'Observation' -- Level 2: Q0510-Q0514
			WHEN concept_code = 'Q0515'
				THEN 'Drug'
			WHEN l2.str = 'Lens, Intraocular (CMS Temporary Codes)'
				OR concept_code = 'Q1003'
				THEN 'Device' -- Level 2: Q1003-Q1005
			WHEN concept_code BETWEEN 'Q2040'
					AND 'Q2043'
				THEN 'Procedure'
			WHEN l2.str = 'Solutions and Drugs (CMS Temporary Codes)'
				AND concept_code NOT IN ('Q2052')
				THEN 'Drug' -- Level 2: Q2004-Q2052
			WHEN l2.str = 'Brachytherapy Radioelements (CMS Temporary Codes)'
				THEN 'Device' -- Level 2: Q3001-Q3001
			WHEN l2.str = 'Telehealth (CMS Temporary Codes)'
				THEN 'Observation' -- Level 2: Q3014-Q3014
			WHEN concept_code IN (
					'Q3025',
					'Q3026'
					)
				THEN 'Drug' -- Injection, Interferon beta
			WHEN l2.str = 'Additional Drugs (CMS Temporary Codes)'
				THEN 'Drug' -- Level 2: Q3027-Q3028
			WHEN l2.str = 'Test, Skin (CMS Temporary Codes)'
				THEN 'Measurement' -- Level 2: Q3031-Q3031
			WHEN l2.str = 'Supplies, Cast (CMS Temporary Codes)'
				THEN 'Device' -- Level 2: Q4001-Q4051
			WHEN l2.str = 'Additional Drug Codes (CMS Temporary Codes)'
				THEN 'Drug' -- Level 2: Q4074-Q4082
			WHEN concept_code BETWEEN 'Q4083'
					AND 'Q4099'
				THEN 'Drug'
			WHEN l2.str = 'Skin Substitutes (CMS Temporary Codes)'
				THEN 'Device' -- Level 2: Q4100-Q4226
			WHEN concept_code IN (
					'Q4261',
					'Q4260',
					'Q4259',
					'Q4258',
					'Q4257',
					'Q4256'
					)
				THEN 'Device' -- Allograft amniotic membrane
			WHEN l2.str = 'Hospice Care (CMS Temporary Codes)'
				THEN 'Observation' --Level 2: Q5001-Q5010
			WHEN l2.str = 'Contrast Agents'
				OR concept_code BETWEEN 'Q9945'
					AND 'Q9949'
				THEN 'Device' -- Level 2: Q9950-Q9969
			WHEN concept_code IN (
					'Q5101',
					'Q5102',
					'Q9955',
					'Q9957',
					'Q9972',
					'Q9973',
					'Q9974',
					'Q9979',
					'Q9980',
					'Q9981'
					)
				THEN 'Drug'
			WHEN concept_code IN (
					'Q9968',
					'Q9953',
					'Q9987',
					'Q9988'
					)
				THEN 'Procedure'
			WHEN concept_code IN (
					'Q9982',
					'Q9983',
					'Q9984',
					'Q9956'
					)
				THEN 'Device' --Radiopharmaceuticals
			WHEN concept_code IN (
					'Q9970',
					'Q9975',
					'Q9976',
					'Q9978',
					'Q9984',
					'Q9985',
					'Q9986',
					'Q9989'
					) -- miscelaneous Q-codes Drugs
				THEN 'Drug'
					-- S codes
			WHEN concept_code BETWEEN 'S0012'
					AND 'S0198' ---'Non-Medicare Drugs'
				THEN 'Drug'
			WHEN concept_code BETWEEN 'S0257'
					AND 'S0265'
				THEN 'Procedure'
			WHEN concept_code BETWEEN 'S0390'
					AND 'S0400'
				THEN 'Procedure'
			WHEN l2.str = 'Provider Services' --(Level 2: S0199-S0400)
				THEN 'Observation' -- includes the previous
			WHEN concept_code = 'S0592'
				THEN 'Procedure' -- Comprehensive contact lens evaluation
			WHEN concept_code BETWEEN 'S0500'
					AND 'S0596'
				THEN 'Device' -- lenses, includes the previous
			WHEN concept_code BETWEEN 'S0601'
					AND 'S0812'
				THEN 'Procedure'
			WHEN concept_code IN (
					'S0830',
					'S8004'
					)
				THEN 'Procedure'
			WHEN concept_code BETWEEN 'S1001'
					AND 'S1040'
				THEN 'Device'
			WHEN concept_code = 'S1090'
				THEN 'Drug' -- Mometasone furoate sinus implant, 370 micrograms
			WHEN concept_code BETWEEN 'S2053'
					AND 'S3000'
				THEN 'Procedure'
			WHEN concept_code IN (
					'S3000',
					'S3005'
					)
				THEN 'Observation' -- Stat lab
			WHEN concept_code IN (
					'S3600',
					'S3601'
					)
				THEN 'Observation' -- stat lab
			WHEN concept_code BETWEEN 'S3600'
					AND 'S3890'
				THEN 'Measurement' -- various genetic tests AND prenatal screenings
			WHEN concept_code BETWEEN 'S3900'
					AND 'S3904'
				THEN 'Procedure' -- EKG AND EMG
			WHEN concept_code BETWEEN 'S3905'
					AND 'S4042'
				THEN 'Procedure' -- IVF procedures
			WHEN concept_code BETWEEN 'S4981'
					AND 'S5014'
				THEN 'Drug' -- various
			WHEN concept_code BETWEEN 'S5035'
					AND 'S5036'
				THEN 'Observation'
			WHEN concept_code BETWEEN 'S5100'
					AND 'S5199'
				THEN 'Observation' -- various care services
			WHEN concept_code BETWEEN 'S5497'
					AND 'S5523'
				THEN 'Procedure' -- Home infusion therapy
			WHEN concept_code BETWEEN 'S5550'
					AND 'S5553'
				THEN 'Drug' -- various Insulin forms-- !!discuss with Christian why he decided, it's a Procuderure Drug -> Procedure
			WHEN concept_code BETWEEN 'S5560'
					AND 'S5571'
				THEN 'Device' -- various Insulin delivery devices
			WHEN concept_code = 'S8030'
				THEN 'Procedure' --Scleral application of tantalum ring(s) for localization of lesions for proton beam therapy
			WHEN concept_code BETWEEN 'S8032'
					AND 'S8092'
				THEN 'Procedure' -- various imaging
			WHEN concept_code = 'S8095'
				THEN 'Device'
			WHEN concept_code = 'S8110'
				THEN 'Measurement' -- Peak expiratory flow rate (physician services)
			WHEN concept_code BETWEEN 'S8096'
					AND 'S8490'
				THEN 'Device'
			WHEN concept_code BETWEEN 'S8930'
					AND 'S8990'
				THEN 'Procedure'
			WHEN concept_code BETWEEN 'S8999'
					AND 'S9007'
				THEN 'Device'
			WHEN concept_code BETWEEN 'S9015'
					AND 'S9075'
				THEN 'Procedure'
			WHEN concept_code BETWEEN 'S9083'
					AND 'S9088'
				THEN 'Observation'
			WHEN concept_code BETWEEN 'S9090'
					AND 'S9110'
				AND concept_code != 'S9098'
				THEN 'Procedure'
			WHEN concept_code BETWEEN 'S9123'
					AND 'S9129'
				AND concept_code != 'S9127'
				THEN 'Procedure' -- home therapy
			WHEN concept_code = 'S9145'
				THEN 'Procedure' -- Insulin pump initiation, instruction in initial use of pump (pump not included)
			WHEN concept_code BETWEEN 'S9150'
					AND 'S9214'
				THEN 'Observation' -- Home management
			WHEN concept_code BETWEEN 'S9328'
					AND 'S9379'
				AND concept_name LIKE 'Home%therapy%'
				THEN 'Procedure' -- home infusions AND home therapy without exact drugs, per diem
			WHEN concept_code BETWEEN 'S9381'
					AND 'S9433'
				THEN 'Observation'
			WHEN concept_code BETWEEN 'S9434'
					AND 'S9435'
				THEN 'Device'
			WHEN concept_code BETWEEN 'S9490'
					AND 'S9562'
				THEN 'Procedure' -- Home infusion therapy, exact group of drugs
					-- T codes
			WHEN concept_code IN (
					'T1500',
					'T2006'
					)
				THEN 'Device'
			WHEN concept_code = 'T1006'
				THEN 'Procedure' -- Alcohol and/or substance abuse services, family/couple counseling
			WHEN hcpc.concept_code IN (
					'T1502',
					'T1503'
					)
				THEN 'Procedure' -- Administration of medication without saying which one (Administration of medication, other than oral and/or injectable, by a health care agency/professional, per visit)
			WHEN hcpc.concept_code BETWEEN 'T1505'
					AND 'T1999'
				THEN 'Device'
			WHEN hcpc.concept_code IN (
					'T2028',
					'T2029'
					)
				THEN 'Device'
			WHEN hcpc.concept_code BETWEEN 'T4521'
					AND 'T5999'
				THEN 'Device'
			WHEN l1.str = 'Temporary National Codes Established by Private Payers'
				THEN 'Observation' -- default for Level 1: S0000-S9999 AND Level 1: T1000-T9999
					-- V codes
			WHEN hcpc.concept_code IN (
					'V2785',
					'V2787',
					'V2788'
					)
				THEN 'Procedure' -- Processing or correcting procedure
			WHEN hcpc.concept_code BETWEEN 'V2624'
					AND 'V2626'
				THEN 'Procedure' -- working on ocular prosthesis
			WHEN hcpc.concept_code IN (
					'V5008',
					'V5010'
					)
				THEN 'Procedure' -- Hearing screening AND assessment of hearing aide
			WHEN hcpc.concept_code IN (
					'V5011',
					'V5014'
					)
				THEN 'Procedure' -- fitting of hearing aide
			WHEN hcpc.concept_code = 'V5020'
				THEN 'Observation' -- Conformity evaluation
			WHEN hcpc.concept_code = 'V5275'
				THEN 'Observation' -- Ear impression, each
			WHEN hcpc.concept_code BETWEEN 'V5300'
					AND 'V5364'
				THEN 'Procedure' -- various screening
			WHEN l1.str = 'V Codes'
				THEN 'Device' -- default for Level 1: V0000-V5999 Vision AND hearing services
			ELSE COALESCE(hcpc.domain_id,'Observation') -- use 'observation' in other cases
			END AS domain_id
	FROM concept_stage hcpc
	LEFT JOIN (
		SELECT code,
			(array(SELECT unnest(regexp_matches(code, '[A-Z]\d{4}', 'g')))) [1] AS lo,
			(array(SELECT unnest(regexp_matches(code, '[A-Z]\d{4}', 'g')))) [2] AS hi,
			str
		FROM sources.mrconso
		WHERE sab = 'HCPCS'
			AND code LIKE 'Level 1%'
		) l1 ON hcpc.concept_code BETWEEN l1.lo
			AND l1.hi
	LEFT JOIN (
		SELECT code,
			(array(SELECT unnest(regexp_matches(code, '[A-Z]\d{4}', 'g')))) [1] AS lo,
			(array(SELECT unnest(regexp_matches(code, '[A-Z]\d{4}', 'g')))) [2] AS hi,
			str
		FROM sources.mrconso
		WHERE sab = 'HCPCS'
			AND code LIKE 'Level 2%'
		) l2 ON hcpc.concept_code BETWEEN l2.lo
			AND l2.hi
	LEFT JOIN (
		SELECT code,
			(array(SELECT unnest(regexp_matches(code, '[A-Z]\d{4}', 'g')))) [1] AS lo,
			(array(SELECT unnest(regexp_matches(code, '[A-Z]\d{4}', 'g')))) [2] AS hi,
			str
		FROM sources.mrconso
		WHERE sab = 'HCPCS'
			AND code LIKE 'Level 3%'
		) l3 ON hcpc.concept_code BETWEEN l3.lo
			AND l3.hi
	WHERE LENGTH(concept_code) > 2
	)
UPDATE concept_stage cs
SET domain_id = t.domain_id
FROM t_domains t
WHERE cs.concept_code = t.concept_code
	AND cs.concept_class_id <> 'HCPCS Class';


--if some codes does not have domain_id pick it up from existing concept table
UPDATE concept_stage cs
SET domain_id = c.domain_id
FROM concept c
WHERE c.concept_code = cs.concept_code
	AND c.vocabulary_id = cs.vocabulary_id
	AND cs.domain_id IS NULL
	AND cs.vocabulary_id = 'HCPCS';

--Procedure Drug codes are handled as Procedures, but this might change in near future. 
--Therefore, we are keeping an interim domain_id='Procedure Drug'
UPDATE concept_stage
SET domain_id = 'Procedure'
WHERE domain_id = 'Procedure Drug';

--4.3. Insert missing codes from manual extraction and assign domains to those concepts can't be assigned automatically
--ProcessManualConcepts
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.ProcessManualConcepts();
END $_$;

--4.4. Since nobody really cares about Modifiers domain, in case it's not covered by the concept_manual, set it to Observation
UPDATE concept_stage
SET domain_id = 'Observation'
WHERE domain_id IS NULL
	AND concept_class_Id = 'HCPCS Modifier';

--5. Fill concept_synonym_stage
INSERT INTO concept_synonym_stage (
	synonym_concept_code,
	synonym_name,
	synonym_vocabulary_id,
	language_concept_id
	)
SELECT DISTINCT HCPC AS synonym_concept_code,
	synonym_name,
	'HCPCS' AS synonym_vocabulary_id,
	4180186 AS language_concept_id -- English
FROM (
	SELECT vocabulary_pack.CutConceptSynonymName(short_description) AS synonym_name,
		HCPC
	FROM sources.anweb_v2
	
	UNION ALL
	
	SELECT vocabulary_pack.CutConceptSynonymName(long_description) AS synonym_name,
		HCPC
	FROM sources.anweb_v2
	) AS s0;

--5.1 add synonyms from the manual table (concept_synonym_manual)
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.ProcessManualSynonyms();
END $_$;

--6. Run HCPCS/ProcedureDrug.sql. This will create all the input files for MapDrugVocabulary.sql
DO $_$
BEGIN
	PERFORM dev_hcpcs.ProcedureDrug();
END $_$;

--7. Run the HCPCS/MapDrugVocabulary.sql. This will produce a concept_relationship_stage with HCPCS to Rx RxNorm/RxNorm Extension relationships
DO $_$
BEGIN
	PERFORM dev_hcpcs.MapDrugVocabulary();
END $_$;

--8. Add upgrade relationships
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	relationship_id,
	vocabulary_id_1,
	vocabulary_id_2,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT concept_code_1,
	concept_code_2,
	'Concept replaced by' AS relationship_id,
	'HCPCS' AS vocabulary_id_1,
	'HCPCS' AS vocabulary_id_2,
	valid_start_date,
	valid_end_date,
	NULL AS invalid_reason
FROM (
	SELECT a.hcpc AS concept_code_1,
		a.xref1 AS concept_code_2,
		coalesce(a.add_date, a.act_eff_dt) AS valid_start_date,
		to_date('20991231', 'yyyymmdd') AS valid_end_date
	FROM sources.anweb_v2 a,
		sources.anweb_v2 b
	WHERE a.xref1 = b.hcpc
		AND a.term_dt IS NOT NULL
		AND b.term_dt IS NULL
	
	UNION ALL
	
	SELECT a.hcpc AS concept_code_1,
		a.xref2,
		coalesce(a.add_date, a.act_eff_dt),
		to_date('20991231', 'yyyymmdd')
	FROM sources.anweb_v2 a,
		sources.anweb_v2 b
	WHERE a.xref2 = b.hcpc
		AND a.term_dt IS NOT NULL
		AND b.term_dt IS NULL
	
	UNION ALL
	
	SELECT a.hcpc AS concept_code_1,
		a.xref3,
		coalesce(a.add_date, a.act_eff_dt),
		to_date('20991231', 'yyyymmdd')
	FROM sources.anweb_v2 a,
		sources.anweb_v2 b
	WHERE a.xref3 = b.hcpc
		AND a.term_dt IS NOT NULL
		AND b.term_dt IS NULL
	
	UNION ALL
	
	SELECT a.hcpc AS concept_code_1,
		a.xref4,
		coalesce(a.add_date, a.act_eff_dt),
		to_date('20991231', 'yyyymmdd')
	FROM sources.anweb_v2 a,
		sources.anweb_v2 b
	WHERE a.xref4 = b.hcpc
		AND a.term_dt IS NOT NULL
		AND b.term_dt IS NULL
	
	UNION ALL
	
	SELECT a.hcpc AS concept_code_1,
		a.xref5,
		coalesce(a.add_date, a.act_eff_dt),
		to_date('20991231', 'yyyymmdd')
	FROM sources.anweb_v2 a,
		sources.anweb_v2 b
	WHERE a.xref5 = b.hcpc
		AND a.term_dt IS NOT NULL
		AND b.term_dt IS NULL
	) i
WHERE NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs_int
		WHERE crs_int.concept_code_1 = i.concept_code_1
			AND crs_int.concept_code_2 = i.concept_code_2
			AND crs_int.vocabulary_id_1 = 'HCPCS'
			AND crs_int.vocabulary_id_2 = 'HCPCS'
			AND crs_int.relationship_id = 'Concept replaced by'
		);

--9. Create hierarchical relationships between HCPCS AND HCPCS class
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	relationship_id,
	vocabulary_id_1,
	vocabulary_id_2,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT a.hcpc AS concept_code_1,
	a.betos AS concept_code_2,
	'Is a' AS relationship_id,
	'HCPCS' AS vocabulary_id_1,
	'HCPCS' AS vocabulary_id_2,
	coalesce(a.add_date, a.act_eff_dt) AS valid_start_date,
	coalesce(a.term_dt, to_date('20991231', 'yyyymmdd')) AS valid_end_date,
	CASE 
		WHEN term_dt IS NULL
			THEN NULL
		WHEN xref1 IS NULL
			THEN 'D' -- deprecated
		ELSE NULL -- upgraded
		END AS invalid_reason
FROM sources.anweb_v2 a
JOIN concept c ON c.concept_code = a.betos
	AND c.concept_class_id = 'HCPCS Class'
	AND c.vocabulary_id = 'HCPCS'
	AND c.invalid_reason IS NULL;

--10. Add all other 'Concept replaced by' relationships
--!! still need to be investigated
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	relationship_id,
	vocabulary_id_1,
	vocabulary_id_2,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT c.concept_code AS concept_code_1,
	c1.concept_code AS concept_code_2,
	r.relationship_id AS relationship_id,
	c.vocabulary_id AS vocabulary_id_1,
	c1.vocabulary_id AS vocabulary_id_2,
	r.valid_start_date,
	r.valid_end_date,
	r.invalid_reason
FROM concept_relationship r,
	concept c,
	concept c1
WHERE c.concept_id = r.concept_id_1
	AND c.vocabulary_id = 'HCPCS'
	AND c1.concept_id = r.concept_id_2
	AND r.relationship_id IN (
		'Concept replaced by',
		'Concept same_as to',
		'Concept alt_to to',
		'Concept was_a to'
		)
	AND r.invalid_reason IS NULL
	AND (
		SELECT COUNT(*)
		FROM concept_relationship r_int
		WHERE r_int.concept_id_1 = r.concept_id_1
			AND r_int.relationship_id = r.relationship_id
			AND r_int.invalid_reason IS NULL
		) = 1
	AND NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		WHERE crs.concept_code_1 = c.concept_code
			AND crs.vocabulary_id_1 = c.vocabulary_id
			AND crs.relationship_id = r.relationship_id
		);

--11. The following codes are mapped incorrectly by map_drug but correctly in concept_relationship_manual
--will be removed after procedure_drug be fixed
DELETE
FROM concept_relationship_stage
WHERE concept_code_1 IN (
		'A9576',
		'A9585',
		'C9275',
		'C9210',
		'C9267',
		'G0010',
		'J0572',
		'J0573',
		'J7042',
		'J7340',
		'J0574',
		'J9175',
		'Q0178',
		'Q0172',
		'Q3022'
		);

--12. Append manual relationships
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.ProcessManualRelationships();
END $_$;

--13. Temporary solution: make concepts that are replaced by the non-existing concepts standard
--CPT4 doesn't have these concepts in sources yet somehow
UPDATE concept_stage cs
SET invalid_reason = NULL,
	standard_concept = 'S'
WHERE NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs_int
		WHERE crs_int.concept_code_1 = cs.concept_code
			AND crs_int.vocabulary_id_1 = cs.vocabulary_id
			AND crs_int.relationship_id IN (
				'Maps to',
				'Concept replaced by',
				'Concept same_as to',
				'Concept alt_to to',
				'Concept was_a to'
				)
			AND crs_int.invalid_reason IS NULL
		)
	AND cs.invalid_reason = 'U';

--14. Working with replacement mappings
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.CheckReplacementMappings();
END $_$;

--15. Add mapping from deprecated to fresh concepts
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.AddFreshMAPSTO();
END $_$;

--16. Deprecate 'Maps to' mappings to deprecated and upgraded concepts
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.DeprecateWrongMAPSTO();
END $_$;

--17. Delete ambiguous 'Maps to' mappings
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.DeleteAmbiguousMAPSTO();
END $_$;

--18. All the codes that have mapping to RxNorm% should get domain_id='Drug'
UPDATE concept_stage cs
SET domain_id = 'Drug'
WHERE EXISTS (
		SELECT 1
		FROM concept_relationship_stage r
		WHERE r.concept_code_1 = cs.concept_code
			AND r.vocabulary_id_1 = cs.vocabulary_id
			AND r.invalid_reason IS NULL
			AND r.relationship_id = 'Maps to'
			AND r.vocabulary_id_2 LIKE 'RxNorm%'
		)
	AND cs.domain_id <> 'Drug';

--19. All concepts mapped to Visit, Provider, Device domains should get the respective domain_id:
UPDATE concept_stage cs
SET domain_id = i.domain_id
FROM (
	SELECT DISTINCT cs1.concept_code,
		FIRST_VALUE(c2.domain_id) OVER (
			PARTITION BY cs1.concept_code ORDER BY CASE c2.domain_id
					WHEN 'Visit'
						THEN 1
					WHEN 'Provider'
						THEN 2
					WHEN 'Device'
						THEN 3
					ELSE 4
					END
			) AS domain_id
	FROM concept_relationship_stage crs
	JOIN concept_stage cs1 ON cs1.concept_code = crs.concept_code_1
		AND cs1.vocabulary_id = crs.vocabulary_id_1
		AND cs1.vocabulary_id = 'HCPCS'
	JOIN concept c2 ON c2.concept_code = crs.concept_code_2
		AND c2.vocabulary_id = crs.vocabulary_id_2
		AND c2.domain_id IN ('Visit', 'Provider', 'Device')
	WHERE crs.relationship_id = 'Maps to'
		AND crs.invalid_reason IS NULL

	UNION ALL

	SELECT DISTINCT cs1.concept_code,
		FIRST_VALUE(c2.domain_id) OVER (
			PARTITION BY cs1.concept_code ORDER BY CASE c2.domain_id
					WHEN 'Visit'
						THEN 1
					WHEN 'Provider'
						THEN 2
					WHEN 'Device'
						THEN 3
					ELSE 4
					END
			)
	FROM concept_relationship cr
	JOIN concept c1 ON c1.concept_id = cr.concept_id_1
		AND c1.vocabulary_id = 'HCPCS'
	JOIN concept c2 ON c2.concept_id = cr.concept_id_2
		AND c2.domain_id IN ('Visit', 'Provider', 'Device')
	JOIN concept_stage cs1 ON cs1.concept_code = c1.concept_code
		AND cs1.vocabulary_id = c1.vocabulary_id
	WHERE cr.relationship_id = 'Maps to'
		AND cr.invalid_reason IS NULL
		AND NOT EXISTS (
			SELECT 1
			FROM concept_relationship_stage crs_int
			WHERE crs_int.concept_code_1 = cs1.concept_code
				AND crs_int.vocabulary_id_1 = cs1.vocabulary_id
				AND crs_int.relationship_id = cr.relationship_id
			)
	) i
WHERE i.concept_code = cs.concept_code
	AND cs.vocabulary_id = 'HCPCS';

--20. All (not only the drugs) concepts having mappings should be NON-standard
UPDATE concept_stage cs
SET standard_concept = NULL
WHERE EXISTS (
		SELECT 1
		FROM concept_relationship_stage r,
			concept c2
		WHERE r.concept_code_1 = cs.concept_code
			AND r.vocabulary_id_1 = cs.vocabulary_id
			AND r.concept_code_2 = c2.concept_code
			AND r.vocabulary_id_2 = c2.vocabulary_id
			AND r.invalid_reason IS NULL
			AND r.relationship_id = 'Maps to'
			AND NOT (
				r.concept_code_1 = r.concept_code_2
				AND r.vocabulary_id_1 = r.vocabulary_id_2
				) --exclude mappings to self
		)
	AND cs.standard_concept IS NOT NULL;

-- At the end, the concept_stage, concept_relationship_stage and concept_synonym_stage tables are ready to be fed into the generic_update script
