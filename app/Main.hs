module Main where

import System.IO (hPutStrLn, stderr)
import qualified Data.Vector as V
import           Data.Aeson
import qualified Data.ByteString.Lazy as B
import           Data.ByteString.Lazy (ByteString)
import           System.Directory (createDirectory, removeDirectoryRecursive, doesDirectoryExist)
import           System.FilePath
import           Control.Monad
import qualified Data.Map as M
import           Data.Map (Map)

import Lib

additionalShortnames :: Map LicenseShortname [LicenseShortname]
additionalShortnames = M.fromList
  [ ("GPL-1.0-only", ["GPL-1.0", "GPL1.0", "GPL1"])
  , ("GPL-2.0-only", ["GPL-2.0", "GPL2.0", "GPL2"])
  , ("GPL-3.0-only", ["GPL-3.0", "GPL3.0", "GPL3"])
  , ("GPL-1.0-or-later", ["GPL-1.0+", "GPL1.0+", "GPL1+"])
  , ("GPL-2.0-or-later", ["GPL-2.0+", "GPL2.0+", "GPL2+"])
  , ("GPL-3.0-or-later", ["GPL-3.0+", "GPL3.0+", "GPL3+"])
  ]

main :: IO ()
main = do
  factsFromSPDX <- loadSPDXFacts "./data/spdx-license-list-data/"
  factsFromBlueOak <- loadBlueOakFacts "./data/Blue_Oak_Council/blue-oak-council-license-list.json"
  factsFromOCPT <- loadOSPTFacts "./data/OpenChainPolicyTemplate/Table.csv"
  factsFromScancode <- loadScancodeFacts "./data/nexB_scancode-toolkit_license_list/"
  factsFromOsadl <- loadOsadlFacts "./data/OSADL/"
  factsFromChooseALicense <- loadChooseALicenseFacts "./data/choosealicense.com/"
  let facts = V.concat [ factsFromSPDX
                       , factsFromBlueOak
                       , factsFromOCPT
                       , factsFromScancode
                       , factsFromOsadl
                       , factsFromChooseALicense
                       ]

  hPutStrLn stderr "... done with collecting data"

  let ids = concatMap (\(LicenseFact _ a _) -> getImpliedShortnames a) $ V.toList factsFromSPDX

  let outputFolder = "_generated/"
  dirExists <- doesDirectoryExist outputFolder
  when dirExists $ do
    removeDirectoryRecursive outputFolder
  createDirectory outputFolder

  let licenses = map (\i -> (i, getLicenseFromFacts i (M.findWithDefault [] i additionalShortnames) facts)) ids
  hPutStrLn stderr "... done with calculating licenses"

  jsons <- mapM (\(i,l) -> let
                    outputFile = i ++ ".json"
                in do
                   B.writeFile (outputFolder </> outputFile) (encode l)
                   return outputFile) licenses
  B.writeFile (outputFolder </> "_all.json") (encode jsons)
