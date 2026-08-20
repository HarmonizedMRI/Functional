function writeDatasetDescriptions(bidsRoot)
%WRITEDATASETDESCRIPTIONS Create BIDS dataset_description.json files.
%
% Creates descriptions for:
%   1. Primary/raw BIDS dataset
%   2. calibration derivative dataset
%
% Existing files are not overwritten.

arguments
    bidsRoot (1,:) char
end

BIDSVersion = '0.0.1';

%% Primary BIDS dataset

filename = fullfile( ...
    bidsRoot, ...
    'dataset_description.json');

metadata = struct;
metadata.Name = 'HarmonizedMRI Functional MRI Dataset';
metadata.BIDSVersion = BIDSVersion;
metadata.DatasetType = 'raw';

writeJsonIfMissing(filename, metadata);


%% Calibration derivatives

calibrationRoot = fullfile( ...
    bidsRoot, ...
    'derivatives', ...
    'calibration');

ensureDirectory(calibrationRoot);

filename = fullfile( ...
    calibrationRoot, ...
    'dataset_description.json');

metadata = struct;
metadata.Name = 'HarmonizedMRI Calibration Derivatives';
metadata.BIDSVersion = BIDSVersion;
metadata.DatasetType = 'derivative';

metadata.GeneratedBy = struct( ...
    'Name', 'HarmonizedMRI calibration');

writeJsonIfMissing(filename, metadata);

