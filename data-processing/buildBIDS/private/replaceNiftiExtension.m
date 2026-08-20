function filename = replaceNiftiExtension(filename, newExtension)
%REPLACENIFTIEXTENSION Replace .nii or .nii.gz with another extension.

arguments
    filename     (1,:) char
    newExtension (1,:) char
end

if endsWith(filename, '.nii.gz')
    filename = [filename(1:end-7) newExtension];

elseif endsWith(filename, '.nii')
    filename = [filename(1:end-4) newExtension];

else
    error('replaceNiftiExtension:InvalidFilename', ...
        'Expected .nii or .nii.gz filename: %s', filename);
end

