{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
module Collectors.OSLC
  ( loadOslcFacts
  ) where

import qualified Prelude as P
import           MyPrelude hiding (id, ByteString)

import qualified Data.Text as T
import qualified Data.Vector as V
import qualified Data.ByteString as B
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as Char8
import           Data.Yaml

import           Model.License

data OSLCUseCase
  = UB
  | MB
  | US
  | MS
  deriving (Show, Generic)
instance ToJSON OSLCUseCase
instance FromJSON OSLCUseCase

data OSLCTerm
  = OSLCTerm
  { termType :: Text
  , termDescription :: Text
  , termUseCases :: Maybe [OSLCUseCase]
  , termComplianceNotes :: Maybe Text
  , termSeeAlso :: Maybe [Text]
  } deriving (Show, Generic)
instance ToJSON OSLCTerm
instance FromJSON OSLCTerm where
  parseJSON = withObject "OSLCTerm" $ \v -> OSLCTerm
    <$> v .: "type"
    <*> v .: "description"
    <*> v .:? "use_cases"
    <*> v .:? "compliance_notes"
    <*> v .:? "seeAlso"

data OSLCData
  = OSLCData
  { name :: LicenseName
  , nameFromFilename :: LicenseName
  , licenseId :: [LicenseName]
  , notes :: Maybe Text
  , terms :: Maybe [OSLCTerm]
  } deriving (Show, Generic)
instance ToJSON OSLCData
instance FromJSON OSLCData where
  parseJSON = withObject "OSLCData" $ \v -> OSLCData
    <$> v .: "name"
    <*> pure ""
    <*> ((v .: "licenseId") <|> fmap (:[]) (v .: "licenseId"))
    <*> v .:? "notes"
    <*> v .:? "terms"
instance LFRaw OSLCData where
  getLicenseFactClassifier _          = LFC ["OSLC", "OSLCFact"]
  getImpliedNames (OSLCData n _ ids _ _) = n : ids

loadOslcFactFromFile :: FilePath -> FilePath -> IO (Vector LicenseFact)
loadOslcFactFromFile oslcFolder oslcFile = let
    fileWithPath = oslcFolder </> oslcFile
    nmffn = dropExtension oslcFile
    convertOslcFromFile oslcdFromFile = let
        spdxIds = licenseId oslcdFromFile
      in map (\spdxId -> LicenseFact oslcdFromFile{ nameFromFilename = nmffn, licenseId = [spdxId] }) spdxIds
  in do
    decoded <- decodeFileEither fileWithPath :: IO (Either ParseException [OSLCData])
    case decoded of
      Left pe -> do
        hPutStrLn stderr ("tried to parse " ++ fileWithPath ++ ":" ++ show pe)
        return V.empty
      Right oslcdFromFiles -> do
        let facts = V.fromList $ concatMap convertOslcFromFile oslcdFromFiles
        mapM_ (\f -> hPutStrLn stderr $ "parsed " ++ fileWithPath ++ " and found: " ++ show (getImpliedNames f)) facts
        return facts

loadOslcFacts :: FilePath -> IO Facts
loadOslcFacts oslcFolder = do
  files <- getDirectoryContents oslcFolder
  let oslcs = filter ("yaml" `isSuffixOf`) files
  facts <- mapM (loadOslcFactFromFile oslcFolder) oslcs
  return (V.concat facts)