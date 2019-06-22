{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
module Collectors.ChooseALicense
  ( loadChooseALicenseFacts
  , extractValueFromText
  , extractListFromText
  ) where

import qualified Prelude as P
import           MyPrelude hiding (ByteString)
import           Collectors.Common

import           Data.List as L
import qualified Data.Vector as V
import qualified Data.ByteString as B
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as Char8

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
  getLicenseFactClassifier _                          = LFC ["choosealicense.com", "CALFact"]
  getImpliedNames CALFactRaw{name = sn, spdxId = sid} = CLSR $ sn : (case sid of
                                                                       Just v  -> [v]
                                                                       Nothing -> [])
  -- getImpliedStatements (CALFactRaw{permissions = perms, conditions = conds, limitations = limits}) =
  --   V.concat $ map (V.fromList . map (\s -> FactStatement s Nothing))
  --                  [ (map ImpliesRight perms)
  --                  , (map ImpliesCondition conds)
  --                  , (map ImpliesLimitation limits)]

extractValueFromText :: [String] -> String -> Maybe String
extractValueFromText ls key = let
    prefix = key ++ ": "
  in case filter (prefix `isPrefixOf`) ls of
       [l] -> stripPrefix prefix l
       _   -> Nothing

extractListFromText :: [String] -> String -> [String]
extractListFromText ls key = let
    prefix = key ++ ":"
    tailIfPresent []     = []
    tailIfPresent (_:as) = as
    lns = map (drop 4) . L.takeWhile (/= "") . tailIfPresent $ L.dropWhile (/= prefix) ls
  in lns

loadCalFactFromFile :: FilePath -> FilePath -> IO LicenseFact
loadCalFactFromFile calFolder calFile = let
    fileWithPath = calFolder </> calFile
    n = dropExtension calFile
  in do
    cnt <- B.readFile fileWithPath
    let ls = lines (Char8.unpack cnt)
    return (LicenseFact ("https://github.com/github/choosealicense.com/blob/gh-pages/_licenses/" ++ calFile)
                        (CALFactRaw n
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
  logThatFactsAreLoadedFrom "choosealicense.com"
  files <- getDirectoryContents calFolder
  let cals = filter ("txt" `isSuffixOf`) files
  facts <- mapM (loadCalFactFromFile calFolder) cals
  return (V.fromList facts)
