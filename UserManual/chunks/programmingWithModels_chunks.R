## @knitr nf-intro

logProbCalcPlus <- nimbleFunction(
    setup = function(model, node) {
        dependentNodes <- model$getDependencies(node)
        valueToAdd <- 1
    },
    run = function(P = double(0)) {
        model[[node]] <<- P + valueToAdd
        return(model$calculate(dependentNodes))
        returnType(double(0))
    })

code <- nimbleCode({
    a ~ dnorm(0, 1)
    b ~ dnorm(a, 1)
})
testModel <- nimbleModel(code, check = FALSE)
logProbCalcPlusA <- logProbCalcPlus(testModel, 'a')
testModel$b <- 1.5
logProbCalcPlusA$run(0.25) 
dnorm(1.25,0,1,TRUE)+dnorm(1.5,1.25,1,TRUE) ## direct validation
testModel$a  ## a was set to 0.5 + valueToAdd


## @knitr nf-compiling

CnfDemo <- compileNimble(testModel, logProbCalcPlusA)
CtestModel <- CnfDemo$testModel
ClogProbCalcPlusA <- CnfDemo$logProbCalcPlusA

## @knitr nf-using
CtestModel$a      ## values were initialized from testModel
CtestModel$b
lpA <- ClogProbCalcPlusA$run(1.5)
lpA
## verify the answer:
dnorm(CtestModel$b, CtestModel$a, 1, log = TRUE) + 
    dnorm(CtestModel$a, 0, 1, log = TRUE) 
CtestModel$a       ## a was modified in the compiled model
testModel$a        ## the uncompiled model was not modified

## @knitr nf-modifyValueToAdd

logProbCalcPlusA$valueToAdd  ## in the uncompiled version
logProbCalcPlusA$valueToAdd <- 2
ClogProbCalcPlusA$valueToAdd  ## or in the compiled version
ClogProbCalcPlusA$valueToAdd <- 3
ClogProbCalcPlusA$run(1.5)
CtestModel$a     ## a == 1.5 + 3

## @knitr nf-RCfun

solveLeastSquares <- nimbleFunction(
    run = function(X = double(2), y = double(1)) {
        ans <- inverse(t(X) %*% X) %*% (t(X) %*% y)
        return(ans)
        returnType(double(2))
    } )

X <- matrix(rnorm(400), nrow = 100)
y <- rnorm(100)
solveLeastSquares(X, y)
CsolveLeastSquares <- compileNimble(solveLeastSquares)
CsolveLeastSquares(X, y)

## @knitr mv-setup-code
## Accepting modelValues as a setup argument
setupFunction = function(propModelValues, model){
    ## Building a modelValues in the setup function 
    savedWeightsConf <- modelValuesConf(vars = 'w',
                                        types = 'double',
                                        sizes = 1)
    savedWeights <- modelValues(conf = savedWeightsConf)
    ## List of nodes to be used in run function
    modelNodes <- model$getNodeNames(stochOnly = TRUE,
                                     includeData = FALSE)
}

## @knitr mv-run-time
runFunction = function(){
    ## gets the number of rows of propSamples
    m <- getsize(propModelValues)

    ## resized savedWeights to have the proper rows
    resize(savedWeights, m)
    for(i in 1:m){
        ## Copying from propSamples to model. 
        ## Node names of propSamples and model must match!
        nimCopy(from = propModelValues, to = model, row = i,
                nodes = modelNodes, logProb = FALSE)
        ## calculates the log likelihood of the model
        targLL <- model$calculate()
        ## retreaves the saved log likelihood from the proposed model
        propLL <- propModelValues['propLL',i][1]
        ## saves the importance weight for the i-th sample 
        savedWeights['w', i][1] <<- exp(targLL - propLL)
    }
    ## does not return anything
}

## @knitr mv-compilation-example
##   Simple model and modelValue for example
targetModelCode <- nimbleCode({
    x ~ dnorm(0,1)
    for(i in 1:4)
        y[i] ~ dnorm(0,1)
})

##	Code for proposal model
propModelCode <- nimbleCode({
	x ~ dnorm(0,2)
	for(i in 1:4)
		y[i] ~ dnorm(0,2)
})

##	Building R models
targetModel = nimbleModel(targetModelCode, check = FALSE)
propModel = nimbleModel(propModelCode, check = FALSE)
cTargetModel = compileNimble(targetModel)
cPropModel = compileNimble(propModel)


sampleMVConf = modelValuesConf(vars = c('x', 'y', 'propLL'), 
    types = c('double', 'double', 'double'), 
    sizes = list(x = 1, y = 4, propLL = 1) )

sampleMV <- modelValues(sampleMVConf)

##   nimbleFunction for generating proposal sample
PropSamp_Gen <- nimbleFunction(
    setup = function(mv, propModel){
        nodeNames <- propModel$getNodeNames()
    },
    run = function(m = integer() ){
        resize(mv, m)
        for(i in 1:m){
            propModel$simulate()
            nimCopy(from = propModel, to = mv, nodes = nodeNames, row = i)
            mv['propLL', i][1] <<- propModel$calculate()
        }
    }
    )

## nimbleFunction for calculating importance weights
## Recylcing setupFunction and runFunction as defined in earlier example
impWeights_Gen <- nimbleFunction(setup = setupFunction,
                                 run = runFunction)
      

## Making instances of nimbleFunctions
## Note that both functions share the same modelValues object
RPropSamp <- PropSamp_Gen(sampleMV, propModel)
RImpWeights <- impWeights_Gen(sampleMV, targetModel)

# Compiling 
CPropSamp <- compileNimble(RPropSamp, project = propModel)
CImpWeights <- compileNimble(RImpWeights, project = targetModel)

#Generating and saving proposal sample of size 10
CPropSamp$run(10)

## Calculating the importance weights and saving to mv
CImpWeights$run()

## Retrieving the modelValues objects
## Extracted objects are C-based modelValues objects

savedPropSamp_1 = CImpWeights$propModelValues
savedPropSamp_2 = CPropSamp$mv

# Subtle note: savedPropSamp_1 and savedPropSamp_2
# both provide interface to the same compiled modelValues objects!
# This is because they were both built from sampleMV.

savedPropSamp_1['x',1]

savedPropSamp_2['x',1]

savedPropSamp_1['x',1] <- 0 ## example of directly setting a value
savedPropSamp_2['x',1]

## Viewing the saved importance weights
savedWeights <- CImpWeights$savedWeights
unlist(savedWeights[['w']])

#Viewing first 3 rows. Note that savedPropSsamp_1['x', 1] was altered 
as.matrix(savedPropSamp_1)[1:3, ]


## @knitr usingMemberFunctions

methodsDemo <- nimbleFunction(
    setup = function() {sharedValue <- 1},
    run = function(x = double(1)) {
        print('sharedValues = ', sharedValue, '\n')
        increment()
        print('sharedValues = ', sharedValue, '\n')
        A <- times(5)
        return(A * x)
        returnType(double(1))
    },
    methods = list(
        increment = function() {
            sharedValue <<- sharedValue + 1
        },
        times = function(factor = double()) {
            return(factor * sharedValue)
            returnType(double())
        }))

methodsDemo1 <- methodsDemo()
methodsDemo1$run(1:10)
methodsDemo1$sharedValue <- 1
CmethodsDemo1 <- compileNimble(methodsDemo1)
CmethodsDemo1$run(1:10)

## @knitr owningMemberFunctions

usePreviousDemo <- nimbleFunction(
    setup = function(initialSharedValue) {
        myMethodsDemo <- methodsDemo()
    },
    run = function(x = double(1)) {
        myMethodsDemo$sharedValue <<- initialSharedValue
        print(myMethodsDemo$sharedValue)
        A <- myMethodsDemo$run(x[1:5])
        print(A)
        B <- myMethodsDemo$times(10)
        return(B)
        returnType(double())
    })

usePreviousDemo1 <- usePreviousDemo(2)
usePreviousDemo1$run(1:10)
CusePreviousDemo1 <- compileNimble(usePreviousDemo1)
CusePreviousDemo1$run(1:10)

## @knitr nimbleFunctionLists

baseClass <- nimbleFunctionVirtual(
    run = function(x = double(1)) {returnType(double())},
    methods = list(
        foo = function() {returnType(double())}
    ))

derived1 <- nimbleFunction(
    contains = baseClass,
    setup = function(){},
    run = function(x = double(1)) {
        print('run 1')
        return(sum(x))
        returnType(double())
    },
    methods = list(
        foo = function() {
        print('foo 1')
        return(rnorm(1, 0, 1))
        returnType(double())
    }))

derived2 <- nimbleFunction(
    contains = baseClass,
    setup = function(){},
    run = function(x = double(1)) {
        print('run 2')
        return(prod(x))
        returnType(double())
    },
    methods = list(
        foo = function() {
        print('foo 2')
        return(runif(1, 100, 200))
        returnType(double())
    }))

useThem <- nimbleFunction(
    setup = function() {
        nfl <- nimbleFunctionList(baseClass)
        nfl[[1]] <- derived1()
        nfl[[2]] <- derived2()
    },
    run = function(x = double(1)) {
        for(i in seq_along(nfl)) {
            print( nfl[[i]]$run(x) )
            print( nfl[[i]]$foo() )
        }
    }
    )

useThem1 <- useThem()
set.seed(0)
useThem1$run(1:5)    
CuseThem1 <- compileNimble(useThem1)
set.seed(0)
CuseThem1$run(1:5)

## @knitr dataStructures

dataNF <- nimbleFunction(
    setup = function() {
        X <- 1
        Y <- as.numeric(c(1, 2)) ## will be a scalar if all sizes are 1
        Z <- matrix(as.numeric(1:4), nrow = 2) ## will be a scalar is all sizes are 1
        setupOutputs(X, Y, Z)
    })

useDataNF <- nimbleFunction(
    setup = function(myDataNF) {},
    run = function(newX = double(), newY = double(1), newZ = double(2)) {
        myDataNF$X <<- newX
        myDataNF$Y <<- newY
        myDataNF$Z <<- newZ
    })

myDataNF <- dataNF()
myUseDataNF <- useDataNF(myDataNF)
myUseDataNF$run(as.numeric(100), as.numeric(100:110),
                matrix(as.numeric(101:120), nrow = 2))
myDataNF$X
myDataNF$Y
myDataNF$Z
myUseDataNF$myDataNF$X

nimbleOptions(useMultiInterfaceForNestedNimbleFunctions = FALSE)
CmyUseDataNF <- compileNimble(myUseDataNF)
CmyUseDataNF$run(-100, -(100:110), matrix(-(101:120), nrow = 2))
CmyDataNF <- CmyUseDataNF$myDataNF
CmyDataNF$X
CmyDataNF$Y
CmyDataNF$Z
