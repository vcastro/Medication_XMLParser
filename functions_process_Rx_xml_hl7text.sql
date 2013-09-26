-- Process xml message from hl7_text field for LMR prescriptions
-- Input: xml message (eg from hl7_text), field (eg med_name, dose, dose_unit)
if object_id(N'dbo.process_med_hl7', N'FN') is not null
	drop function dbo.process_med_hl7
go

create function dbo.process_med_hl7 (
	@hl7 varchar(max),
	@field varchar(100)
	)
returns varchar(max)
as
begin
	declare @result varchar(max)

	if patindex('%' + @field + '>%', @hl7) > 0
	begin
		declare @first_match varchar(500)

		set @first_match = substring(@hl7, patindex('%' + @field + '>%', @hl7) + len(@field) + 1, len(@hl7))
		set @result = substring(@first_match, 0, patindex('%</LMR%', @first_match))

		if len(@result) = 0
		begin
			set @result = null
		end
	end
	else
	begin
		set @result = null
	end

	return @result
end
go

-- standardize drug frequency using custom list
if object_id(N'dbo.standardize_drug_frequency', N'FN') is not null
	drop function dbo.standardize_drug_frequency
go

create function dbo.standardize_drug_frequency (@frequency varchar(100))
returns varchar(500)
as
begin
	declare @result varchar(500)

	set @frequency = replace(@frequency, '.', '')

	select @result = case when @frequency like '%PRN%' then 'PRN' when @frequency like '%5ID%' then '5ID' when @frequency like '%QID%' then 'QID' when @frequency like '%QDS%' then 'QID' when @frequency like '%Q6H%' then 'QID' when @frequency like '%TID%' then 'TID' when @frequency like '%Q8H%' then 'TID' when @frequency like '%AC%' then 'TID' when @frequency like '%BID%' then 'BID' when @frequency like '%Q12H%' then 'BID' when @frequency like '%QD%' then 'QD' when @frequency like '%QHS%' then 'QD' when @frequency like '%QAM%' then 'QD' when @frequency like '%HS%' then 'QD' when @frequency like '%QPM%' then 'QD' when @frequency like '%Q PM%' then 'QD' when @frequency like '%Q AM%' then 'QD' when @frequency like '%Q24%' then 'QD' when @frequency = 'daily' then 'QD' when @frequency = 'x1' then 'QD' when @frequency = 'at bedtime' then 'QD' when @frequency = 'AM' then 'QD' when @frequency = 'Q day' then 'QD' when @frequency like '%QOD%' then 'QOD' when @frequency like '%QWEEK%' then 'QWK' else 'Nonstandard' end

	if @frequency is null
	begin
		set @result = null
	end

	return @result
end
go

-- compute units per day from drug frequency
if object_id(N'dbo.drug_frequency_in_unitsperday', N'FN') is not null
	drop function dbo.drug_frequency_in_unitsperday
go

create function dbo.drug_frequency_in_unitsperday (@std_frequency varchar(500))
returns numeric
as
begin
	return case when @std_frequency = 'QD' then 1 when @std_frequency = 'BID' then 2 when @std_frequency = 'TID' then 3 when @std_frequency = 'QID' then 4 when @std_frequency = '5ID' then 5 when @std_frequency = 'QOD' then 0.5 when @std_frequency = 'QWK' then 0.143 else null end
end
go

-- standardize duration -- cleans invalid durations by setting them to null
if object_id(N'dbo.standardize_drug_duration', N'FN') is not null
	drop function dbo.standardize_drug_duration
go

create function dbo.standardize_drug_duration (@duration varchar(100))
returns numeric
as
begin
	declare @result numeric

	set @result = case when isnumeric(@duration) = 1 then case when @duration < cast(1 as numeric) or @duration > cast(365 as numeric) then null when @duration = cast(99 as numeric) then null else @duration end else null end

	return @result
end
go

-- standardize drug refills - clean and standardize using custom rules
if object_id(N'dbo.standardize_drug_refills', N'FN') is not null
	drop function dbo.standardize_drug_refills
go

create function dbo.standardize_drug_refills (@refills varchar(100))
returns numeric
as
begin
	declare @result numeric

	set @refills = replace(replace(@refills, 'x', ''), '#', '')
	set @refills = replace(replace(replace(@refills, 'NR', '0'), 'None', '0'), 'o', '0')
	set @refills = replace(replace(@refills, 'One', '1'), '0ne', '1')
	set @result = case when isnumeric(@refills) = 1 and len(@refills) < 3 and @refills <> '-' then case when @refills between cast(0 as numeric) and cast(60 as numeric) then cast(@refills as numeric) else null end when @refills is null then null when @refills like '%1%year%' or @refills like '%1%yr%' then 12 else null end

	return @result
end
go

-- standardize drug dispense - clean and standardize using custom rules
if object_id(N'dbo.standardize_drug_dispense', N'FN') is not null
	drop function dbo.standardize_drug_dispense
go

create function dbo.standardize_drug_dispense (@dispense varchar(100))
returns numeric
as
begin
	declare @result numeric

	set @dispense = replace(@dispense, 'x', '')
	set @dispense = replace(@dispense, '#', '')

	if isnumeric(@dispense) = 1 and @dispense <> '-' and left(@dispense, 1) <> '.'
	begin
		set @result = case when @dispense < cast(1 as numeric) or @dispense > cast(1500 as numeric) then null else @dispense end
	end
	else
	begin
		set @result = null
	end

	return @result
end
go

-- standardize drug dispense units - clean and standardize using custom rules
if object_id(N'dbo.standardize_drug_dispenseunits', N'FN') is not null
	drop function dbo.standardize_drug_dispenseunits
go

create function dbo.standardize_drug_dispenseunits (@dispenseunits varchar(100))
returns varchar(100)
as
begin
	declare @result varchar(100)

	set @result = case when @dispenseunits like '%TAB%' or @dispenseunits like '%CAP%' or @dispenseunits like '%PILL%' then 'Tablet/Capsule' when @dispenseunits like '%MON%' or @dispenseunits like '%MOS%' then 'Months Supply' when @dispenseunits like '%DAY%' then 'Days Supply' when @dispenseunits like '%WEEK%' then 'Weeks Supply' else 'Nonstandard' end

	if @dispenseunits is null
	begin
		set @result = null
	end

	return @result
end
go

-- calculate drug exposure days for each rx using duration, dispense amount, frequency and refill info
if object_id(N'dbo.calculate_exposure_days', N'FN') is not null
	drop function dbo.calculate_exposure_days
go

create function dbo.calculate_exposure_days (
	@duration varchar(500),
	@dispense varchar(500),
	@dispenseunits varchar(500),
	@frequency varchar(500),
	@refills varchar(500)
	)
returns int
as
begin
	declare @result numeric
	declare @std_duration numeric
	declare @std_dispense numeric
	declare @std_refills numeric
	declare @std_unitsperday numeric
	declare @std_dispenseunits varchar(100)

	set @std_duration = dbo.standardize_drug_duration(@duration)
	set @std_dispense = dbo.standardize_drug_dispense(@dispense)
	set @std_dispenseunits = dbo.standardize_drug_dispenseunits(@dispenseunits)
	set @std_refills = dbo.standardize_drug_refills(@refills)
	set @std_unitsperday = dbo.drug_frequency_in_unitsperday(dbo.standardize_drug_frequency(@frequency))

	if @std_duration is null
	begin
		set @result = case when @std_refills is null then null when @std_dispenseunits = 'Months supply' then @std_dispense * 30 * (@std_refills + 1) when @std_dispenseunits = 'Weeks supply' then @std_dispense * 7 * (@std_refills + 1) when @std_dispenseunits = 'Days supply' then @std_dispense * (@std_refills + 1) when @std_dispenseunits = 'Tablet/Capsule' then (@std_dispense / (isnull(@std_unitsperday, 0) + 0.1)) * (@std_refills + 1) else null end
	end
	else
	begin
		set @result = @duration * (@std_refills + 1)
	end

	return @result
end
go


