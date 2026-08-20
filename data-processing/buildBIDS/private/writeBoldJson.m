function writeBoldJson( ...
    filename, ...
    phaseEncodingDirection, ...
    totalReadoutTime, ...
    overwrite)
%WRITEBOLDJSON Write minimal BIDS BOLD JSON sidecar.

arguments
    filename               (1,:) char
    phaseEncodingDirection (1,1) string
    totalReadoutTime       (1,1) double {mustBePositive}
    overwrite              (1,1) logical = false
end

if isfile(filename) && ~overwrite
    fprintf('Skipping existing JSON:\n  %s\n', filename);
    return
end

metadata = struct;
metadata.PhaseEncodingDirection = phaseEncodingDirection;
metadata.TotalReadoutTime = totalReadoutTime;

text = jsonencode(metadata, PrettyPrint=true);

fid = fopen(filename, 'w');

if fid < 0
    error('writeBoldJson:OpenFailed', ...
        'Could not open file for writing: %s', filename);
end

cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '%s\n', text);

fprintf('Created JSON:\n  %s\n', filename);

