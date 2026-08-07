function copyIfPresent(sourceFilename, destinationFilename, overwrite)
%COPYIFPRESENT Copy a file if it exists.
%
% copyIfPresent(sourceFilename, destinationFilename)
% copyIfPresent(sourceFilename, destinationFilename, overwrite)
%
% If the source file does not exist, a warning is issued and the function
% returns without error.

arguments
    sourceFilename      (1,:) char
    destinationFilename (1,:) char
    overwrite           (1,1) logical = false
end

if ~isfile(sourceFilename)
    warning('copyIfPresent:MissingFile', ...
        'File not found:\n  %s', sourceFilename);
    return
end

copyFileChecked( ...
    sourceFilename, ...
    destinationFilename, ...
    overwrite);

