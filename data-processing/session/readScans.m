function scans = readScans(filename, vendor)
%READSCANS Read scan locations from scans.txt.
%
% The first line of scans.txt contains the raw-data directory.
% Subsequent lines contain:
%
%   <scan type> <file or directory>
%
% Example:
%
%   /data/sub00004/.../Exam7498/
%   cal   Series15
%   2d    Series14
%   rest  Series16

lines = readlines(filename);
lines = strip(lines);
lines(lines == "") = [];

if isempty(lines)
    error('Empty scans file: %s', filename);
end

scans.datadir = char(lines(1));

for ii = 2:numel(lines)
    fields = split(lines(ii));
    fields(fields == "") = [];

    if numel(fields) ~= 2
        error('Invalid line in %s: %s', filename, lines(ii));
    end

    type = char(fields(1));
    name = char(fields(2));

    % Use a valid MATLAB field name for the 2D calibration scan.
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

end


function name = resolveScan(datadir, name, vendor)
% Resolve vendor-specific raw-data filenames.

if ~strcmpi(vendor, 'GE')
    return;
end

% GE scans.txt entries specify the Series directory rather than
% the ScanArchive file itself.
seriesDir = fullfile(datadir, name);

D = dir(seriesDir);
D = D(~[D.isdir]);

if isempty(D)
    error('No raw-data file found in %s.', seriesDir);
end

% Preserve the behavior of the previous reconstruction for now.
name = fullfile(name, D(end).name);

