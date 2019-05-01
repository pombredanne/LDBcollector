{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
module Collectors.ChooseALicense
  ( loadChooseALicenseFacts
  , extractValueFromText
  , extractListFromText
  ) where

import Prelude hiding (id)

import           System.FilePath
import           System.Directory
import           Data.List as L
import qualified Data.Text as T
import qualified Data.Vector as V
import           Debug.Trace (trace)
import qualified Data.ByteString as B
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as Char8

import           Data.Aeson
import           GHC.Generics

import           Model.License

data CALFactRaw
  = CALFactRaw
  { name :: LicenseName
  , title :: Maybe String
  , spdxId :: Maybe LicenseName
  , featured :: Maybe String
  , hidden :: Maybe String
  , description :: Maybe String
  , how :: Maybe String
  , permissions :: [String]
  , conditions :: [String]
  , limitations :: [String]
  , content :: ByteString
  } deriving (Show, Generic)
instance ToJSON ByteString where
  toJSON = toJSON . Char8.unpack
instance ToJSON CALFactRaw
instance LFRaw CALFactRaw where
  getImpliedNames CALFactRaw{name = sn, spdxId = sid} = sn : (case sid of
                                                                Just v  -> [v]
                                                                Nothing -> [])
  getType _                                           = "CALFact"

extractValueFromText :: [String] -> String -> Maybe String
extractValueFromText ls key = let
    prefix = key ++ ": "
  in case filter (prefix `isPrefixOf`) ls of
       [l] -> stripPrefix prefix l
       _   -> Nothing

-- permissions:
--   - commercial-use
--   - modifications
--   - distribution
--   - private-use

-- conditions:
--   - include-copyright

-- limitations:
--   - liability
--   - warranty
extractListFromText :: [String] -> String -> [String]
extractListFromText ls key = let
    prefix = key ++ ":"
    tailIfPresent []     = []
    tailIfPresent (a:as) = as
    lns = map (drop 4) . L.takeWhile (/= "") . tailIfPresent $ L.dropWhile (/= prefix) ls
  in lns

loadCalFactFromFile :: FilePath -> FilePath -> IO LicenseFact
loadCalFactFromFile calFolder calFile = let
    fileWithPath = calFolder </> calFile
    n = dropExtension calFile
  in do
    cnt <- B.readFile fileWithPath
    let ls = lines (Char8.unpack cnt)
    return (mkLicenseFact "choosealicense.com" (CALFactRaw n
                                                (extractValueFromText ls "title")
                                                (extractValueFromText ls "spdx-id")
                                                (extractValueFromText ls "featured")
                                                (extractValueFromText ls "hidden")
                                                (extractValueFromText ls "description")
                                                (extractValueFromText ls "how")
                                                (extractListFromText ls "permissions")
                                                (extractListFromText ls "conditions")
                                                (extractListFromText ls "limitations")
                                                cnt))

loadChooseALicenseFacts :: FilePath -> IO Facts
loadChooseALicenseFacts calFolder = do
  files <- getDirectoryContents calFolder
  let cals = filter ("txt" `isSuffixOf`) files
  facts <- mapM (loadCalFactFromFile calFolder) cals
  return (V.fromList facts)
