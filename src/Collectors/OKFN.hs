{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Collectors.OKFN
    ( loadOkfnFacts
    , okfnLFC
    ) where

import qualified Prelude as P
import           MyPrelude hiding (id)
import           Collectors.Common

import qualified Data.Text as T
import qualified Data.Vector as V
import           Data.Csv hiding ((.=))
import qualified Data.Csv as C
import qualified Data.ByteString
import qualified Data.ByteString.Lazy as BL
import           Data.FileEmbed (embedFile)

import           Model.License

-- id,domain_content,domain_data,domain_software,family,is_generic,maintainer,od_conformance,osd_conformance,status,title,url,legacy_ids
data OkfnFact
  = OkfnFact LicenseName -- id
             Bool -- domain_content
             Bool -- domain_data
             Bool -- domain_software
             (Maybe Bool) -- is_generic
             Text -- maintainer
             Text -- od_conformance
             Text -- osd_conformance
             Text -- status
             Text -- title
             Text -- url
             [LicenseName] -- legacy_ids
  deriving (Show, Generic)
instance ToJSON OkfnFact where
  toJSON (OkfnFact id domain_content domain_data domain_software is_generic maintainer od_conformance osd_conformance status title url legacy_ids) =
    object [ "id" .= id
           , "domain_content" .= domain_content
           , "domain_data" .= domain_data
           , "domain_software" .= domain_software
           , "is_generic" .= is_generic
           , "maintainer" .= maintainer
           , "od_conformance" .= od_conformance
           , "osd_conformance" .= osd_conformance
           , "status" .= status
           , "title" .= title
           , "url" .= url
           , "legacy_ids" .= legacy_ids ]
okfnURL :: URL
okfnURL = "https://github.com/okfn/licenses/blob/master/licenses.csv"
okfnLICENSE :: LicenseFactLicense
okfnLICENSE = LFLWithURL "https://opendatacommons.org/licenses/pddl/1-0/" "PDDL-1.0"
okfnLFC :: LicenseFactClassifier
okfnLFC = LFCWithURLAndLicense okfnURL okfnLICENSE "Open Knowledge International"
instance LicenseFactClassifiable OkfnFact where
  getLicenseFactClassifier _ = okfnLFC
instance LFRaw OkfnFact where
  getImpliedNames (OkfnFact id _ _ _ _ _ _ _ _ title _ lIds) = CLSR (id : (T.unpack title : lIds))
  getImpliedId o@(OkfnFact id _ _ _ _ _ _ _ _ _ _ _)         = mkRLSR o 40 id
  getImpliedURLs (OkfnFact _ _ _ _ _ _ _ _ _ _ url _)        = CLSR [(Nothing, T.unpack url)]
  getImpliedJudgement o@(OkfnFact _ _ _ _ _ _ _ _ s _ _ _)   = if s == "active"
    then NoSLSR
    else mkSLSR o (NegativeJudgement ("The license is" ++ T.unpack s))
instance FromNamedRecord OkfnFact where
  parseNamedRecord r = let
      handleBool :: Text -> Bool
      handleBool "True" = True
      handleBool "False" = False
      handleBool "TRUE" = True
      handleBool "FALSE" = False
      handleBool _ = undefined -- TODO
      handleMaybeBool :: Text -> Maybe Bool
      handleMaybeBool "True" = Just True
      handleMaybeBool "False" = Just False
      handleMaybeBool "TRUE" = Just True
      handleMaybeBool "FALSE" = Just False
      handleMaybeBool _ = Nothing
      handleList :: Text -> [LicenseName]
                -- "[u'nasa1.3']" --> ["nasa1.3"]
      handleList str =
        if str == ""
        then []
        else (map T.unpack . T.splitOn ("',u'") . T.dropEnd 2 . T.drop 3) str
    in OkfnFact <$> r C..: "id"
                <*> (fmap handleBool (r C..: "domain_content" :: Parser Text) :: Parser Bool)
                <*> (fmap handleBool (r C..: "domain_data" :: Parser Text) :: Parser Bool)
                <*> (fmap handleBool (r C..: "domain_software" :: Parser Text) :: Parser Bool)
                <*> (fmap handleMaybeBool (r C..: "is_generic" :: Parser Text) :: Parser (Maybe Bool))
                <*> r C..: "maintainer"
                <*> r C..: "od_conformance"
                <*> r C..: "osd_conformance"
                <*> r C..: "status"
                <*> r C..: "title"
                <*> r C..: "url"
                <*> (fmap handleList (r C..: "legacy_ids" :: Parser Text) :: Parser [LicenseName])

okfnFile :: BL.ByteString
okfnFile = BL.fromStrict $(embedFile "data/okfn-licenses.csv")

loadOkfnFacts :: IO Facts
loadOkfnFacts = do
  logThatFactsAreLoadedFrom "Open Knowledge International"
  case (C.decodeByName okfnFile :: Either String (Header, V.Vector OkfnFact)) of
        Left err -> do
          putStrLn err
          return V.empty
        Right (_, v) -> return $ V.map (LicenseFact $ Just okfnURL) v
