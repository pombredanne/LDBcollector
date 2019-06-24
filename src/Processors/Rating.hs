{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
module Processors.Rating
    ( Rating (..)
    , ratingRules
    , applyRatingRules, applyDefaultRatingRules
    ) where

import qualified Prelude as P
import           MyPrelude

import qualified Data.Text as T
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy as BL
import           Control.Monad
import           Control.Monad.Trans.Writer.Strict (execWriter, tell)
import qualified Data.Map as M

import           Model.License

data Rating
  = RGo -- can be used
  | RAtention -- needs more atention
  | RStop -- needs aproval
  | RNoGo -- can't be used
  | RUnknown [Rating]
  deriving (Show, Generic, Eq)

-- to keep track of current possibilities
data RatingState
  = RatingState
  { rsGo :: Bool
  , rsAtention :: Bool
  , rsStop :: Bool
  , rsNoGo :: Bool
  }
ratingFromRatingState :: RatingState -> Rating
ratingFromRatingState rs = let
    mapFromState :: (RatingState -> Bool) -> Rating -> RatingState -> Maybe Rating
    mapFromState getter result state = if getter state
                                       then Just result
                                       else Nothing
    ratingFromSetOfRatings :: [Rating] -> Rating
    ratingFromSetOfRatings [r] = r
    ratingFromSetOfRatings rs' = RUnknown rs'
  in ratingFromSetOfRatings . catMaybes $ map (\f -> f rs) [ mapFromState rsGo RGo
                                                           , mapFromState rsAtention RAtention
                                                           , mapFromState rsStop RStop
                                                           , mapFromState rsNoGo RNoGo
                                                           ]

type RatingStateMutator
  = RatingState -> RatingState

initialReportRatingState :: RatingState
initialReportRatingState = RatingState True True True True -- everything is possible

removeRatingFromState :: Rating -> RatingStateMutator
removeRatingFromState RGo       rs = rs{rsGo = False}
removeRatingFromState RAtention rs = rs{rsAtention = False}
removeRatingFromState RStop     rs = rs{rsStop = False}
removeRatingFromState RNoGo     rs = rs{rsNoGo = False}
removeRatingFromState _         rs = rs -- TODO??

setRatingOfState :: Rating -> RatingStateMutator
setRatingOfState RGo       = removeRatingFromState RAtention . removeRatingFromState RStop . removeRatingFromState RNoGo
setRatingOfState RAtention = removeRatingFromState RGo . removeRatingFromState RStop . removeRatingFromState RNoGo
setRatingOfState RStop     = removeRatingFromState RGo . removeRatingFromState RAtention . removeRatingFromState RNoGo
setRatingOfState RNoGo     = removeRatingFromState RGo . removeRatingFromState RAtention . removeRatingFromState RStop
setRatingOfState _         = removeRatingFromState RGo . removeRatingFromState RAtention . removeRatingFromState RStop . removeRatingFromState RNoGo -- TODO??

type RatingRuleFun
  = License -> RatingStateMutator
data RatingRule
  = RatingRule
  { rrDescription :: Text
  , rrFunction :: RatingRuleFun
  }
instance Show RatingRule where
  show (RatingRule desc _) = T.unpack desc

applyRatingRules :: [RatingRule] -> License -> Rating
applyRatingRules rrls l = ratingFromRatingState $ foldl' (\oldS rrf -> rrf l oldS) initialReportRatingState (map rrFunction rrls)

applyDefaultRatingRules :: License -> Rating
applyDefaultRatingRules = applyRatingRules ratingRules

ratingRules :: [RatingRule]
ratingRules = let
    addRule desc fun = tell . (:[]) $ RatingRule desc fun
  in execWriter $ do
    addRule "should have at least one positive rating to be Go" $ let
        fun b j = b || (case j of
                           PositiveJudgement _ -> True
                           _ -> False)
        hasPossitiveJudgements l = M.foldl' fun False . unpackSLSR $ getImpliedJudgement l
      in \l -> if hasPossitiveJudgements l
               then id
               else removeRatingFromState RGo
    addRule "only known NonCopyleft Licenses can be go" $
      \l -> case getCalculatedCopyleft l of
              Just NoCopyleft -> id
              _ -> removeRatingFromState RGo
    addRule "possitive Rating by BlueOak helps" $ \l -> case M.lookup (LFC ["BlueOak", "BOEntry"])  (unpackSLSR $ getImpliedJudgement l) of
                                                          Just (PositiveJudgement _) -> removeRatingFromState RNoGo . removeRatingFromState RStop -- TODO: remove RAt* if no negative Judgement?
                                                          Just (NegativeJudgement _) -> removeRatingFromState RGo
                                                          _                          -> id
    addRule "Fedora bad Rating implies at least Stop" $ \l -> case M.lookup (LFC ["FedoraProjectWiki", "FPWFact"])  (unpackSLSR $ getImpliedJudgement l) of
      Just (NegativeJudgement _) -> removeRatingFromState RGo . removeRatingFromState RAtention
      _                          -> id
--     addRule "should have no negative ratings to be Go" $ let

  

-- ruleFunctionFromCondition :: (Map LicenseFactClassifier Judgement -> Bool) -> RatingStateMutator -> RatingRuleFun
-- ruleFunctionFromCondition condition fun l = if condition l
--                                             then fun
--                                             else id
-- negativeRuleFunctionFromCondition :: (Map LicenseFactClassifier Judgement -> Bool) -> RatingStateMutator -> RatingRuleFun
-- negativeRuleFunctionFromCondition condition = ruleFunctionFromCondition (not . condition)

-- applyRatingRules :: [RatingRule] -> Map LicenseFactClassifier Judgement -> Rating
-- applyRatingRules rrs stmts = let
--     applyRatingRules' = foldr (`rrFunction` stmts) initialReportRatingState
--   in ratingFromRatingState (applyRatingRules' rrs)

-- {-
--  - RatingConfiguration
--  -}

-- data RatingConfiguration
--   = RatingConfiguration (Map LicenseName Rating) -- Overwrites
--                         [RatingRule] -- ratingRules

-- mkRatingConfiguration :: (Map LicenseName Rating) -> RatingConfiguration
-- mkRatingConfiguration rOs = let
--     actualRatingRules :: [RatingRule]
--     actualRatingRules = let
--         addRule desc fun = tell . (:[]) $ RatingRule desc fun
--         getStatementsWithLabel label = V.filter (\stmt -> extractLicenseStatementLabel stmt == label)
--         getStatementsWithLabelFromSource label source = V.filter (\stmt -> (extractLicenseStatementLabel stmt == label)
--                                                                             && (_factSourceClassifier stmt == source))

--       in execWriter $ do
--         addRule "should have at least one positive rating to be Go" $ let
--             fn = (== 0) . V.length . getStatementsWithLabel possitiveRatingLabel
--           in ruleFunctionFromCondition fn (removeRatingFromState RGo)
--         addRule "should have no negative ratings to be Go" $ let
--             fn = (> 0) . V.length . getStatementsWithLabel negativeRatingLabel
--           in ruleFunctionFromCondition fn (removeRatingFromState RGo)
--         addRule "Fedora bad Rating implies at least Stop" $ let
--             fn = (> 0) . V.length . getStatementsWithLabelFromSource negativeRatingLabel (LFC ["FedoraProjectWiki", "FPWFact"])
--           in ruleFunctionFromCondition fn (removeRatingFromState RGo . removeRatingFromState RAtention)
--         addRule "Blue Oak Lead Rating implies at least Stop" $ let
--             fn = (> 0) . V.length . getStatementsWithLabelFromSource negativeRatingLabel (LFC ["BlueOak", "BOEntry"])
--           in ruleFunctionFromCondition fn (removeRatingFromState RGo . removeRatingFromState RAtention)

--   in RatingConfiguration rOs actualRatingRules

-- emptyRatingConfiguration :: RatingConfiguration
-- emptyRatingConfiguration = mkRatingConfiguration M.empty

-- applyRatingConfiguration :: RatingConfiguration -> (LicenseName, License) -> Rating
-- applyRatingConfiguration (RatingConfiguration rOs rrs) (ln,l) = let
--     calculatedR = applyRatingRules rrs (getStatementsFromLicense l)
--   in M.findWithDefault calculatedR ln rOs

-- applyEmptyRatingConfiguration :: (LicenseName, License) -> Rating
-- applyEmptyRatingConfiguration = applyRatingConfiguration emptyRatingConfiguration
