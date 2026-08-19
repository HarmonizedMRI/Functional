function scans = readScans(filename, dataRoot, sessionID, vendor)
%READSCANS Read scan locations from scans.txt.
%
% scans = readScans(filename, dataRoot, sessionID, vendor)
%
% The first line of scans.txt contains the original data directory.
% Everything before sessionID in that path is ignored and replaced by
% dataRoot.
%
% This allows existing scans.txt files containing machine-specific
% absolute paths to be reused without editing.
%
% Example scans.txt:
%
%   /mnt/storage/.../sub00012-umich-mr750-20250115-1/raw/Exam15678/
%   b0    Series9
%   cal   Series15
%   2d    Series14
%   rest  Series16
%
% If dataRoot is:
%
%   /home/user/data
%
% then the data directory is resolved as:
%
%   /home/user/data/sub00012-umich-mr750-20250115-1/raw/Exam15678

lines = readlines(filename);
lines = strip(lines);
lines(lines == "") = [];

if isempty(lines)
    error('Empty scans file: %s', filename);
end

%% Resolve data directory

originalDataDir = char(lines(1));

% Normalize separators so paths written on another platform can still
% be parsed.
originalDataDir = strrep(originalDataDir, '\', '/');

parts = split(string(originalDataDir), '/');
parts(parts == "") = [];

idx = find(parts == string(sessionID), 1);

if isempty(idx)
    error('Session "%s" not found in data path: %s', ...
        sessionID, originalDataDir);
end

% Preserve everything from the session directory onward, while replacing
% the machine-specific parent directory with dataRoot.
relativePath = fullfile(parts{idx:end});
scans.datadir = fullfile(dataRoot, relativePath);

if ~isfolder(scans.datadir)
    warning('Data directory not found: %s', scans.datadir);
end

%% Read individual scan entries

for ii = 2:numel(lines)

    fields = split(lines(ii));
    fields(fields == "") = [];

    if numel(fields) ~= 2
        error('Invalid line in %s: %s', filename, lines(ii));
    end

    type = char(fields(1));
    name = char(fields(2));

    % MATLAB structure field names cannot begin with a number.
    if strcmp(type, '2d')
        type = 'cal2d';
    end

    entry.name = resolveScan(scans.datadir, name, vendor);

    if isfield(scans, type)
        scans.(type)(end+1) = entry;
    else
        scans.(type) = entry;
    end
end

return


function name = resolveScan(datadir, name, vendor)
%RESOLVESCAN Resolve vendor-specific scan filenames.

if ~strcmpi(vendor, 'GE')
    % For non-GE data, keep the scans.txt entry as-is, but warn if the
    % resolved path does not exist.
    resolved = fullfile(datadir, name);

    if ~isfile(resolved) && ~isfolder(resolved)
        warning('Scan not found: %s', resolved);
    end

    return;
end

% GE scans.txt entries specify the Series directory rather than the
% ScanArchive file itself.
seriesDir = fullfile(datadir, name);

if ~isfolder(seriesDir)
    warning('GE Series directory not found: %s', seriesDir);
    return;
end

D = dir(seriesDir);
D = D(~[D.isdir]);

if isempty(D)
    warning('No raw-data file found in %s.', seriesDir);
    return;
end

% Preserve the behavior of the previous reconstruction code for now:
% use the last non-directory entry in the Series directory.
name = fullfile(name, D(end).name);

resolved = fullfile(datadir, name);

if ~isfile(resolved)
    warning('Raw data file not found: %s', resolved);
end

return
