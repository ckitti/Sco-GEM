%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% ecModel_script
%
% - Reconstructs ecScoGEM from scoGEM
% - Make M145 and M1152 specific models
% - Simulations with proteome pool
% - Prepare proteomics data
% - Make sample-specific proteome constrained models
% - Random sampling of solution spaces
%
% Eduard Kerkhoven, 2018-12-04
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ecDir = pwd();
root  = regexprep(ecDir,'(.*)\\[^\\]*\\.*','$1');

%% - Reconstructs ecScoGEM from scoGEM
model       = importModel([root '/ModelFiles/xml/scoGEM.xml']);
cd([ecDir '/reconstruction'])
%Remove blocked rxns + correct model.rev
model   = preprocessModel(model);
ecModel = construct_ecScoGEM(model);
load([root '/scrap/ecScoGEM_noManualMods.mat']);

[ecModel,modifications] = manualModifications(ecModel);

%% - Make M145 and M1152 specific models
% For M1152, remove reactions involving act, red, cpk and cda clusters
% Get genes from M1152 paper (Gomez-Escribano & Bibb, 2011;
% doi:10.1111/j.1751-7915.2010.00219.x)
actGenes = cellstr(strcat('SCO', string(5074:5089)));
redGenes = cellstr(strcat('SCO', string(5879:5895)));
cpkGenes = cellstr(strcat('SCO', string(6272:6286)));
cdaGenes = cellstr(strcat('SCO', string(3212:3246)));
allGenes = [actGenes,redGenes,cpkGenes,cdaGenes];
allGenes = allGenes(contains(allGenes,model.genes));
modelM1152 = removeGenes(model,allGenes,true,true,true);
clear actGenes redGenes cpkGenes cdaGenes allGenes

cd([ecDir '/gecko/geckomat/utilities'])
ecModel_M1152 = getSubset_ecModel(modelM1152, ecModel);

rates.M145 = dlmread([root '/ComplementaryData/growth/M145/average/M145_estimated_rates.csv'],',',1,0);
GlcUptake.M145  = -rates.M145(1,4);%
GluUptake.M145  = -rates.M145(1,5);%
gRate.M145      = rates.M145(1,3);%
ecModel=setParam(ecModel,'ub',{'EX_glc__D_e_REV',...
    'EX_glu__L_e_REV','EX_nh4_e_REV'},[GlcUptake.M145,GluUptake.M145,0]);

rates.M1152 = dlmread([root '/ComplementaryData/growth/M1152/average/M1152_estimated_rates.csv'],',',1,0);
GlcUptake.M1152  = -rates.M1152(1,4);%
GluUptake.M1152  = -rates.M1152(1,5);%
gRate.M1152      = rates.M1152(1,3);%
ecModel_M1152=setParam(ecModel_M1152,'ub',{'EX_glc__D_e_REV',...
    'EX_glu__L_e_REV','EX_nh4_e_REV'},[GlcUptake.M1152,GluUptake.M1152,0]);

save([root '/scrap/ecScoGEM_M145M1152.mat'],'ecModel*');

%% - Simulations with proteome pool
sigma   = 0.5;
Ptot    = 0.456; % As reported by Shabab et al. (1996) Microbiol.

cd([ecDir '/gecko/geckomat/limit_proteins'])

[ecModel_M145_pool, optSigma] = getConstrainedModel(ecModel,'',sigma,Ptot,gRate.M1152,modifications,'scoGEM');
sol=solveLP(ecModel_M145_pool)

[ecModel_M1152_pool, optSigma] = getConstrainedModel(ecModel_M1152,'',sigma,Ptot,gRate.M1152,modifications,'scoGEM');
sol=solveLP(ecModel_M1152_pool)

% conditions  = num2cell(sample(:,[1,3]),1);
% conditions  = strcat(conditions{:,1},{'_'},conditions{:,2});
% T = topUsedEnzymes(transpose(sol_pool),model_pool(1),conditions,'scoGEM',false,10);
% writetable(T,['../../../../../ComplementaryData/ecmodel/ecScoGEM_pool_topUsedEnzymes.txt'])


%% - Prepare proteomics data
sample      = [cellstr(repmat('M145',9,1));cellstr(repmat('M1152',8,1))];
sample(:,2) = num2cell([21;29;33;37;41;45;49;53;57;33;41;45;49;53;57;61;65]);

sigma   = 1;
Ptot    = 0.456; % As reported by Shabab et al. (1996) Microbiol.
[f,~]   = measureAbundance(ecModel.enzymes);
cd(ecDir)
data    = prepareProteomicsM1152M145;
pIDs    = data.genes;

%% - Make sample-specific proteome constrained models
cd([ecDir '/gecko/geckomat/limit_proteins'])
for i=1:9%length(sample(:,1))
    protData = data.mean(:,i) + data.std(:,i);
    prot(i).model = constrainEnzymes(ecModel,Ptot,sigma,f,[],pIDs,protData);%,GlcUptake);
    cd ([ecDir 'simulation'])
    [prot(i).model, prot(i).gRate] = fixFluxes(prot(i).model,sample{i,1},sample{i,2});
    if prot(i).gRate<0
        prot(i).gRate=0.0070;
    end
    cd([ecDir '/gecko/geckomat/limit_proteins'])
    [prot(i).model,prot(i).enzUsages,prot(i).modifications] = flexibilizeProteins(prot(i).model,prot(i).gRate);
end

for i=10:length(sample(:,1))
    protData = data.mean(:,i) + data.std(:,i);
    prot(i).model = constrainEnzymes(ecModel_M1152,Ptot,sigma,f,[],pIDs,protData);%,GlcUptake);
    cd ([ecDir 'simulation'])
    [prot(i).model, prot(i).gRate] = fixFluxes(prot(i).model,sample{i,1},sample{i,2});
    if prot(i).gRate<0
        prot(i).gRate=0.0070;
    end
    cd([ecDir '/gecko/geckomat/limit_proteins'])
    [prot(i).model,prot(i).enzUsages,prot(i).modifications] = flexibilizeProteins(prot(i).model,prot(i).gRate);
end

save([root '/scrap/proteomeModels.mat'],'prot');

%% - Random sampling of solution spaces

[~,goodRxns1] = randomSampling(prot(1).model,2);
[~,goodRxns2] = randomSampling(prot(11).model,2);

for i=1:9
    disp(['Sample: ' num2str(i)])
    prot(i).sol = solveLP(prot(i).model,1);
    tmp = setParam(prot(i).model,'eq',1,-prot(i).sol.f);
    tmp = randomSampling(tmp,100,true,false,false,goodRxns1);
    tmp = mean(tmp,2);
    [prot(i).enzUsagesRS,prot(i).proteinRS] = enzymeUsage(prot(i).model,tmp);
end

for i=10:length(sample(:,1))
    disp(['Sample: ' num2str(i)])
    prot(i).sol = solveLP(prot(i).model,1);
    tmp = setParam(prot(i).model,'eq',1,-prot(i).sol.f);
    tmp = randomSampling(tmp,100,true,false,false,goodRxns2);
    tmp = mean(tmp,2);
    [prot(i).enzUsagesRS,prot(i).proteinRS] = enzymeUsage(prot(i).model,tmp);
end

for i=1:length(sample(:,1))
    exportModel(prot(i).model,...
    [root,'/ModelFiles/xml/',sample{i,1},'_',num2str(sample{i,2}),'.xml']);
end


for i=1:9
    out(:,i)=prot(i).enzUsagesRS;
end
out=full(out);
clear out

save([root '/ModelFiles/mat/ecProtModels.mat'],'ecModel','ecModel_M1152','prot')

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%