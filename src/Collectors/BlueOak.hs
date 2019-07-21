{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Collectors.BlueOak
  ( loadBlueOakFacts
  , loadBlueOakFactsFromString
  , decodeBlueOakData -- for testing
  , blueOakLFC
  ) where

import qualified Prelude as P
import           MyPrelude hiding (id)

import qualified Data.Text as T
import qualified Data.Vector as V
import qualified Data.ByteString
import qualified Data.ByteString.Lazy as B
import           Data.ByteString.Lazy (ByteString)
import           Data.FileEmbed (embedFile)

import           Model.License
import           Collectors.Common

data BlueOakLicense
 = BlueOakLicense
 { name :: String
 , id :: String
 , url :: String
 } deriving (Show,Generic)
instance FromJSON BlueOakLicense
instance ToJSON BlueOakLicense

data BlueOakRating
 = BlueOakRating
 { rating :: String
 , licenses :: [BlueOakLicense]
 } deriving (Show)
instance FromJSON BlueOakRating where
  parseJSON = withObject "BlueOakRating" $ \v -> BlueOakRating
    <$> v .: "name"
    <*> v .: "licenses"

data BlueOakData
  = BlueOakData
  { version :: String
  , ratings :: [BlueOakRating]
  } deriving (Show,Generic)
instance FromJSON BlueOakData where
  parseJSON = withObject "BlueOakData" $ \v -> BlueOakData
    <$> v .: "version"
    <*> v .: "ratings"

decodeBlueOakData :: ByteString -> BlueOakData
decodeBlueOakData bs = case decode bs of
  Just bod -> bod
  Nothing  -> trace "ERR: Failed to parse Blue Oak JSON" (BlueOakData "-1" [])

data BOEntry
  = BOEntry String -- licenseListVersion
            String -- rating
            BlueOakLicense -- data
  deriving Generic
instance ToJSON BOEntry where
  toJSON (BOEntry _ r l) = object [ "BlueOakRating" .= r
                                  , "name" .= name l
                                  , "id" .= id l
                                  , "url" .= url l
                                  , "isPermissive" .= True ]
instance Show BOEntry where
  show (BOEntry _ _ j) = show j

blueOakLFC :: LicenseFactClassifier
blueOakLFC = LFC "BlueOak License List"

instance LFRaw BOEntry where
  getLicenseFactClassifier _               = blueOakLFC
  getImpliedFullName boe@(BOEntry _ _ bol) = mkRLSR boe 40 (name bol)
  getImpliedNames (BOEntry _ _ bol)        = CLSR [id bol]
  getImpliedJudgement boe@(BOEntry _ r _)  = let
      ratingText = "Rating is: " ++ r
    in SLSR (getLicenseFactClassifier boe) $
       case r of
         "Lead" -> NegativeJudgement ratingText
         _      -> PositiveJudgement ratingText
  getImpliedURLs (BOEntry _ _ bol)         = let
      urlbol = url bol
      isSPDX = ("spdx.org" `isInfixOf` urlbol)
      urlClass = if isSPDX
                 then Just "SPDX"
                 else Nothing
    in CLSR [(urlClass, urlbol)]
  getImpliedCopyleft boe                   = mkSLSR boe NoCopyleft

loadBlueOakFactsFromString :: ByteString -> Facts
loadBlueOakFactsFromString bs = let
    bod = decodeBlueOakData bs
    bodVersion = version bod
    bodRatings = ratings bod
    ratingConverter (BlueOakRating r ls) = map (LicenseFact (Just "https://blueoakcouncil.org/list") . BOEntry bodVersion r) ls
    facts = concatMap ratingConverter bodRatings
  in trace ("INFO: the version of BlueOak is: " ++ bodVersion) $ V.fromList facts

blueOakFile :: Data.ByteString.ByteString
blueOakFile = $(embedFile "data/blue-oak-council-license-list.json")

loadBlueOakFacts :: IO Facts
loadBlueOakFacts = let
    blueOakFile :: Data.ByteString.ByteString
    blueOakFile = $(embedFile "data/blue-oak-council-license-list.json")
  in do
    logThatFactsAreLoadedFrom "Blue Oak Council License List"
    return (loadBlueOakFactsFromString (B.fromStrict blueOakFile))
