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

-- id,domain_content,domain_data,domain_software,family,is_generic,maintainer,od_conformance,osd_conformance,status,title,url
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
  deriving (Show, Generic)
instance ToJSON OkfnFact where
  toJSON (OkfnFact id domain_content domain_data domain_software is_generic maintainer od_conformance osd_conformance status title url) =
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
           , "url" .= url ]
okfnLFC :: LicenseFactClassifier
okfnLFC = LFC "Open Knowledge International"
instance LFRaw OkfnFact where
  getLicenseFactClassifier _ = okfnLFC
  getImpliedNames (OkfnFact id _ _ _ _ _ _ _ _ title _) = CLSR [id, T.unpack title]
  getImpliedId o@(OkfnFact id _ _ _ _ _ _ _ _ _ _)      = mkRLSR o 40 id
  getImpliedURLs (OkfnFact _ _ _ _ _ _ _ _ _ _ url)     = CLSR [(Nothing, T.unpack url)]
instance FromNamedRecord OkfnFact where
  parseNamedRecord r = let
      handleBool :: Text -> Bool
      handleBool "TRUE" = True
      handleBool "FALSE" = False
      handleBool _ = undefined -- TODO
      handleMaybeBool :: Text -> Maybe Bool
      handleMaybeBool "TRUE" = Just True
      handleMaybeBool "FALSE" = Just False
      handleMaybeBool _ = Nothing
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

okfnFile :: BL.ByteString
okfnFile = BL.fromStrict $(embedFile "data/okfn-licenses.csv")

loadOkfnFacts :: IO Facts
loadOkfnFacts = do
  logThatFactsAreLoadedFrom "Open Knowledge International"
  case (C.decodeByName okfnFile :: Either String (Header, V.Vector OkfnFact)) of
        Left err -> do
          putStrLn err
          return V.empty
        Right (_, v) -> return $ V.map (LicenseFact $ Just "https://github.com/okfn/licenses/blob/master/licenses.csv") v

