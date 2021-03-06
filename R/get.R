#' lake_wiki
#' @param lake_name character
#' @param map logical produce map of lake location?
#' @param ... arguments passed to maps::map
#' @export
#' @examples \dontrun{
#' lake_wiki("Lake Peipsi")
#' lake_wiki("Flagstaff Lake (Maine)")
#' lake_wiki("Lake George (Michigan-Ontario)")
#' lake_wiki("Lake Michigan", map = TRUE, "usa")
#' lake_wiki("Lac La Belle, Michigan")
#' lake_wiki("Lake Antoine")
#' lake_wiki("Lake Baikal")
#' lake_wiki("Dockery Lake (Michigan)")
#' lake_wiki("Coldwater Lake")
#' lake_wiki("Bankson Lake")
#' lake_wiki("Fisher Lake (Michigan)")
#' lake_wiki("Beals Lake")
#' lake_wiki("Devils Lake (Michigan)")
#' lake_wiki("Lake Michigan")
#' lake_wiki("Fletcher Pond")
#' lake_wiki("Lake Bella Vista (Michigan)")
#' lake_wiki("Lake Mendota")
#' lake_wiki("Lake Mendota", map = TRUE, "usa")
#' lake_wiki("Lake Nipigon", map = TRUE, regions = "Canada")
#' lake_wiki("Trout Lake (Wisconsin)")
#' lake_wiki("Rutland Water")
#'
#' # throws warning on redirects
#' lake_wiki("Beals Lake")
#'
#' # ignore notability box
#' lake_wiki("Rainbow Lake (Waterford Township, Michigan)")
#' }

lake_wiki <- function(lake_name, map = FALSE, ...){

  res <- get_lake_wiki(lake_name)

  if(map){
    map_lake_wiki(res, ...)
  }

  if(!is.null(res)){
    res <- tidy_lake_df(res)
  }

  res
}


#' get_lake_wiki
#' @import WikipediR
#' @import rvest
#' @importFrom xml2 read_html
#' @param lake_name character
#' @param cond character stopping condition
#' @examples \dontrun{
#' get_lake_wiki("Lake Nipigon")
#' }
get_lake_wiki <- function(lake_name, cond = NA){
  # display page link
  page_metadata <- page_info("en","wikipedia", page = lake_name)$query$pages

  page_link <- page_metadata[[1]][["fullurl"]]
  message(paste0("Retrieving data from: ", page_link))

  get_content <- function(lake_name){
    res <- WikipediR::page_content("en", "wikipedia", page_name = lake_name,
                                   as_wikitext = FALSE)
    res <- res$parse$text[[1]]
    res <- xml2::read_html(res, encoding = "UTF-8")
    res
  }

  is_redirect <- function(res){
    length(
      grep("redirect",
           rvest::html_attr(rvest::html_nodes(res, "div"), "class"))
      ) >  0
  }

  page_redirect <- function(res){
    rvest::html_attr(rvest::html_nodes(res, "a"), "title")[1]
  }

  res <- get_content(lake_name)

  if(is_redirect(res)){
    lake_name <- page_redirect(res)
    message(paste0("Attempting redirect to '", lake_name, "'"))
    res <- get_content(lake_name)
  }

  is_not_lake_page <- function(res, meta_index){
    no_meta_index <- length(meta_index) == 0
    if(no_meta_index) meta_index <- 1
    res <- rvest::html_table(res[meta_index])[[1]]

    no_meta_index & !any(suppressWarnings(stringr::str_detect(unlist(res), c("lake",
                                          "tributaries",
                                          "outflow",
                                          "elevation",
                                          "coordinates"))))
  }

  res <- tryCatch({

    res <- rvest::html_nodes(res, "table")
    meta_index <- grep("infobox vcard", rvest::html_attr(res, "class"))

    if(is_not_lake_page(res, meta_index)) stop(cond)

    if(length(meta_index) == 0) meta_index <- 1

    res <- rvest::html_table(res[max(meta_index)])[[1]]

    # create missing names
    # rm rows that are just repeating the lake name
    if(all(nchar(names(res)) <  3)){
      names(res) <- res[1,]
    }
    res <- res[!apply(res, 1, function(x) all(x == names(res)[1])),]

    res <- suppressWarnings(apply(res, 2,
                        function(x) stri_encode(stri_trans_general(x,
                                      "Latin-ASCII"), "", "UTF-8")))
  },
  error = function(cond){
    message("'", paste0(lake_name,
                        "' is missing a metadata table or
                        does not have its own page"))
    return(NA)
  }
  )

  if(any(!is.na(res))){
    # format coordinates ####
    has_multiple_rows <- !is.null(nrow(res))
    if(has_multiple_rows){
      coords <- res[which(res[,1] == "Coordinates"), 2]
    }else{
      coords <- res[2]
    }

    is_tidy_coords <- nchar(coords) < 33

    if(!is_tidy_coords){
      coords <- strsplit(coords, "\\/")[[1]]
      coords <- sapply(coords, function(x) strsplit(x, "Coordinates: "))
      coords <- sapply(coords, function(x) strsplit(x, " "))
      coords <- paste(unlist(coords), collapse = ",")
      coords <- strsplit(coords, ",")[[1]]

      coords <- coords[!(seq_len(length(coords)) %in%
                           c(which(nchar(coords) == 0),
                             grep("W", coords),
                             grep("E", coords),
                             grep("S", coords),
                             grep("N", coords)))][1:2]

      coords <- gsub("\\[.\\]", "", coords)

      if(any(nchar(coords) > 5)){
        coords <- sapply(gsub(";", "", coords),
                    function(x) substring(x, 1, nchar(x) - 1))
        coords <- paste(as.numeric(coords), collapse = ",")
      }else{
        coords <- paste(as.numeric(gsub(";", "", coords)), collapse = ",")
      }
    }else{
      is_west <- length(grep("W", coords)) > 0
      coords <- strsplit(coords, ", ")[[1]]
      coords <- strsplit(coords, "[^0-9]+")
      coords <- lapply(coords, as.numeric)
      coords <- lapply(coords, function(x) x[1:3])
      coords <- unlist(lapply(coords, dms2dd))
      if(is_west){
        coords[2] <- coords[2] * -1
      }
      coords <- paste(coords, collapse = ",")
    }

    if(has_multiple_rows){
      res[which(res[,1] == "Coordinates"), 2] <- coords
    }else{
      res[2] <- coords
    }

    # rm junk rows
    if(has_multiple_rows){
      if(any(res[,1] == "")){
        res <- res[-which(res[,1] == ""),]
      }
      if(any(nchar(res[,1]) > 20)){
        res <- res[-which(nchar(res[,1]) > 20),]
      }
      if(length(grep("well-defined", res[,1])) != 0){
        res <- res[!(1:nrow(res) %in% grep("well-defined", res[,1])),]
        message("Shore length is not a well-defined measure.")
      }
      if(length(grep("Islands", res[,1])) != 0){
        res <- res[!(1:nrow(res) %in% grep("Islands", res[,1])),]
      }
      if(length(grep("Settlements", res[,1])) != 0){
        res <- res[!(1:nrow(res) %in% grep("Settlements", res[,1])),]
      }
      if(length(grep("Sign", res[,1])) != 0){
        res <- res[!(1:nrow(res) %in% grep("Sign", res[,1])),]
      }
    }

    res
  }
  }
