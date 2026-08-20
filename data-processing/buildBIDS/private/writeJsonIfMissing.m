function writeJsonIfMissing(filename, metadata)
%WRITEJSONIFMISSING Write a JSON file unless it already exists.

arguments
    filename (1,:) char
    metadata (1,1) struct
end

if isfile(filename)
    fprintf('Keeping existing JSON:\n  %s\n', filename);
    return
end

ensureDirectory(fileparts(filename));

text = jsonencode(metadata, PrettyPrint=true);

fid = fopen(filename, 'w');

if fid < 0
    error('writeJsonIfMissing:OpenFailed', ...
        'Could not open file for writing: %s', filename);
end

cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '%s\n', text);

fprintf('Created JSON:\n  %s\n', filename);

