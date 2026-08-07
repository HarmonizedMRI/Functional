function copySessionToBIDS(info)
%COPYSESSIONTOBIDS Copy one internal session into the source BIDS dataset.

arguments
    info (1,1) struct
end

copyAnat(info);
copyFmap(info);
copyBOLD(info);

