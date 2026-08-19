function F = getScanFiles(S, acquisition)
%GETSCANFILES Return full paths to scan data files.
%
% F = getScanFiles(S, acquisition)
%
% Inputs:
%   S            Session structure returned by loadSession
%   acquisition  Acquisition type, e.g. 'pulseq' or 'product'
%
% Output:
%   F            Structure containing full paths for each scan type
%
% Example:
%   S = loadSession(configRoot, dataRoot, sessionID);
%   F = getScanFiles(S, 'pulseq');
%
%   F.cal
%   F.cal2d
%   F.rest

if ~isfield(S, 'scans') || ~isfield(S.scans, acquisition)
    error('No "%s" scans found for session %s.', acquisition, S.id);
end

scans = S.scans.(acquisition);

if ~isfield(scans, 'datadir')
    error('No data directory defined for "%s" scans.', acquisition);
end

F = struct;

fields = fieldnames(scans);

for ii = 1:numel(fields)

    type = fields{ii};

    % datadir is metadata, not a scan.
    if strcmp(type, 'datadir')
        continue;
    end

    entries = scans.(type);

    files = cell(1, numel(entries));

    for jj = 1:numel(entries)
        files{jj} = fullfile(scans.datadir, entries(jj).name);

        if ~isfile(files{jj}) && ~isfolder(files{jj})
            warning('Scan not found: %s', files{jj});
        end
    end

    % Keep the common single-scan case convenient.
    if numel(files) == 1
        F.(type) = files{1};
    else
        F.(type) = files;
    end
end

