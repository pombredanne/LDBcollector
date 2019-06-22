{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Model.Fact
  ( module X
  , LicenseName
  , LicenseFactClassifier (..)
  , LFRaw (..)
  , LicenseFact (..), extractLicenseFactClassifier
  , Facts
  ) where

import qualified Prelude as P
import           MyPrelude

import qualified Data.Text as T
import qualified Data.Vector as V

import Model.Statement as X

type LicenseName
  = String
class (Show a, ToJSON a) => LFRaw a where
  getLicenseFactClassifier :: a -> LicenseFactClassifier
  -- Statements:
  getImpliedNames :: a -> CollectedLicenseStatementResult LicenseName
  getImpliedNames _ = NoCLSR
  getImpliedId :: a -> RankedLicenseStatementResult LicenseName
  getImpliedId _ = NoRLSR
  getImpliedURLs :: a -> CollectedLicenseStatementResult (String, URL)
  getImpliedURLs _ = NoCLSR
  getImpliedText :: a -> RankedLicenseStatementResult Text
  getImpliedText _ = NoRLSR

newtype LicenseFactClassifier
  = LFC [Text]
  deriving (Eq, Generic)
instance Show LicenseFactClassifier where
  show (LFC brc) = T.unpack $ T.intercalate "/" brc
instance ToJSON LicenseFactClassifier where
  toJSON lfc = toJSON $ show lfc

type URL
  = String
data LicenseFact
  = forall a. (LFRaw a)
  => LicenseFact (Maybe URL) a
extractLicenseFactClassifier :: LicenseFact -> LicenseFactClassifier
extractLicenseFactClassifier (LicenseFact _ a)         = getLicenseFactClassifier a

instance Show LicenseFact where
  show (LicenseFact _ a) = show a
instance ToJSON LicenseFact where
  toJSON (LicenseFact (Just url) a) = let
      lfc = getLicenseFactClassifier a
    in object [ tShow lfc .= mergeAesonL [toJSON a
                                         , object [ "_sourceURL" .= toJSON url ]] ]
  toJSON (LicenseFact Nothing a) = let
      lfc = getLicenseFactClassifier a
    in object [ tShow lfc .= toJSON a ]
instance LFRaw LicenseFact where
  getLicenseFactClassifier (LicenseFact _ raw)         = getLicenseFactClassifier raw
  getImpliedNames (LicenseFact _ raw)                  = getImpliedNames raw

type Facts
  = Vector LicenseFact
