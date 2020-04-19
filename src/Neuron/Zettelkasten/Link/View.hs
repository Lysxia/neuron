{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | Special Zettel links in Markdown
module Neuron.Zettelkasten.Link.View
  ( neuronLinkExt,
    renderZettelLink,
  )
where

import Data.Some
import Lucid
import Neuron.Web.Route (Route (..), routeUrlRelWithQuery)
import Neuron.Zettelkasten.ID
import Neuron.Zettelkasten.Link
import Neuron.Zettelkasten.Link.Theme (LinkTheme (..))
import Neuron.Zettelkasten.Markdown (MarkdownLink (..))
import Neuron.Zettelkasten.Query
import Neuron.Zettelkasten.Store
import Neuron.Zettelkasten.Tag (Tag (unTag))
import Neuron.Zettelkasten.Zettel
import Relude
import qualified Rib
import qualified Text.MMark.Extension as Ext
import Text.MMark.Extension (Extension, Inline (..))
import Text.URI.QQ (queryKey)

-- | MMark extension to transform neuron links to custom views
neuronLinkExt :: HasCallStack => ZettelStore -> Extension
neuronLinkExt store =
  Ext.inlineRender $ \f -> \case
    inline@(Link inner uri _title) ->
      let mlink = MarkdownLink (Ext.asPlainText inner) uri
       in case neuronLinkFromMarkdownLink mlink of
            Right (Just nl) ->
              renderNeuronLink store nl
            Right Nothing ->
              f inline
            Left e ->
              error e
    inline ->
      f inline

-- | Render the custom view for the given neuron link
renderNeuronLink :: Monad m => ZettelStore -> NeuronLink -> HtmlT m ()
renderNeuronLink store = \case
  NeuronLink (Query_ZettelByID zid, _conn, linkTheme) ->
    -- Render a single link
    renderZettelLink linkTheme $ lookupStore zid store
  NeuronLink (q@(Query_ZettelsByTag _pats), _conn, linkTheme) -> do
    -- Render a list of links
    toHtml $ Some q
    let zettels = sortOn Down $ zettelID <$> runQuery store q
    ul_ $ do
      forM_ zettels $ \zid ->
        li_ $ renderZettelLink linkTheme $ lookupStore zid store
  NeuronLink (q@(Query_Tags _), (), ()) -> do
    -- Render a list of tags
    toHtml $ Some q
    let tags = runQuery store q
    ul_ $ do
      forM_ tags $ \(unTag -> tag) -> do
        let tagUrl = routeUrlRelWithQuery Route_Search [queryKey|tag|] tag
        li_ $ a_ [href_ tagUrl] $ toHtml tag

-- | Render a link to an individual zettel.
renderZettelLink :: forall m. Monad m => LinkTheme -> Zettel -> HtmlT m ()
renderZettelLink ltheme Zettel {..} = do
  let zurl = Rib.routeUrlRel $ Route_Zettel zettelID
      renderDefault :: ToHtml a => a -> HtmlT m ()
      renderDefault linkInline = do
        span_ [class_ "zettel-link"] $ do
          span_ [class_ "zettel-link-idlink"] $ do
            a_ [href_ zurl] $ toHtml linkInline
          span_ [class_ "zettel-link-title"] $ do
            toHtml zettelTitle
  case ltheme of
    LinkTheme_Default ->
      -- Special consistent styling for Zettel links
      -- Uses ZettelID as link text. Title is displayed aside.
      renderDefault zettelID
    LinkTheme_WithDate ->
      case zettelIDDay zettelID of
        Just day ->
          renderDefault $ show @Text day
        Nothing ->
          -- Fallback to using zid
          renderDefault zettelID
    LinkTheme_Simple ->
      renderZettelLinkSimpleWith zurl (zettelIDText zettelID) zettelTitle

-- | Render a normal looking zettel link with a custom body.
renderZettelLinkSimpleWith :: forall m a. (Monad m, ToHtml a) => Text -> Text -> a -> HtmlT m ()
renderZettelLinkSimpleWith url title body =
  a_ [class_ "zettel-link item", href_ url, title_ title] $ do
    span_ [class_ "zettel-link-title"] $ do
      toHtml body
