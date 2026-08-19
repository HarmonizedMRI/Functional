function copyBOLD(info)
%COPYBOLD Copy product and Pulseq BOLD images for one session.
%
% Source filename conventions:
%
%   task_run*.nii  -> task-vismotor
%   rest_run*.nii  -> task-rest
%
% Product and Pulseq acquisitions are processed independently.

arguments
    info (1,1) struct
end

validateSessionInfo(info);

productDir = fullfile(info.srcDir, 'product');
pulseqDir  = fullfile(info.srcDir, 'pulseq');

ensureDirectory(fullfile(info.sessionDir, 'func'));

runs = {
    'task_run*.nii', 'task_run', 'vismotor'
    'rest_run*.nii', 'rest_run', 'rest'
};

%% Product BOLD

if isfolder(productDir)

    for iType = 1:size(runs,1)

        pattern   = runs{iType,1};
        prefix    = runs{iType,2};
        taskLabel = runs{iType,3};

        files = dir(fullfile(productDir, pattern));

        for iFile = 1:numel(files)

            sourceName = files(iFile).name;

            runNumber = parseRunNumber(sourceName, prefix);

            if isempty(runNumber)
                warning('copyBOLD:InvalidProductFilename', ...
                    'Skipping unrecognized product filename: %s', ...
                    sourceName);
                continue
            end

            sourceFilename = fullfile(productDir, sourceName);

            suffix = sprintf( ...
                'task-%s_acq-product_run-%02d_bold.nii', ...
                taskLabel, ...
                runNumber);

            destinationFilename = makeBidsPath( ...
                info, ...
                'func', ...
                suffix);

            copyIfPresent( ...
                sourceFilename, ...
                destinationFilename);

        end
    end

else
    warning('copyBOLD:MissingProductDir', ...
        'Product directory not found: %s', productDir);
end


%% Pulseq BOLD

if isfolder(pulseqDir)

    for iType = 1:size(runs,1)

        pattern   = runs{iType,1};
        prefix    = runs{iType,2};
        taskLabel = runs{iType,3};

        files = dir(fullfile(pulseqDir, pattern));

        for iFile = 1:numel(files)

            sourceName = files(iFile).name;

            runNumber = parseRunNumber(sourceName, prefix);

            if isempty(runNumber)
                warning('copyBOLD:InvalidPulseqFilename', ...
                    'Skipping unrecognized Pulseq filename: %s', ...
                    sourceName);
                continue
            end

            pulseqSource = fullfile(pulseqDir, sourceName);

            suffix = sprintf( ...
                'task-%s_acq-pulseq_run-%02d_bold.nii', ...
                taskLabel, ...
                runNumber);

            pulseqDestination = makeBidsPath( ...
                info, ...
                'func', ...
                suffix);

            % Use matching product run only as the NIfTI geometry reference.
            productReference = fullfile( ...
                productDir, ...
                sprintf('%s%d.nii', prefix, runNumber));

            if ~isfile(productReference)
                warning('copyBOLD:MissingProductReference', ...
                    ['Cannot fix Pulseq NIfTI header because the matching ' ...
                     'product run was not found:\n  %s'], ...
                    productReference);
                continue
            end

            writePulseqNifti( ...
                pulseqSource, ...
                productReference, ...
                pulseqDestination);

        end
    end

else
    warning('copyBOLD:MissingPulseqDir', ...
        'Pulseq directory not found: %s', pulseqDir);
end

