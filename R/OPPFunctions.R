#' Download OPP tracking data from Movebank
#'
#' @description This function downloads OPP tracking data from Movebank and returns a
#' dataframe with combined tracking and reference data for all deployments.
#'
#' @param study List of Movebank project ids.
#' @param login Stored Movebank login credentials if provided, otherwise function
#'will prompt users to enter credentials.
#' @param start_month Earliest month (1-12) to include in output.
#' @param end_month Latest month (1-12) to include in output.
#' @param season Vector describing the season data can be applied to, eg. 'Breeding (Jun-Jul)'
#'
#' @details The function can be passed a list of movebank study IDs and will append
#'data from all studies.
#'
#' @examples
#'# download ANMU project data from two studies, for May only
#'my_data <- opp_download_data(study = c(1895716931, 1897273090),
#'                             login = NULL, start_month = 5, end_month = 5,
#'                             season = 'Incubation')
#'
#'@export

opp_download_data <- function(study,
                              login = NULL,
                              start_month = NULL,
                              end_month = NULL,
                              season = NULL
) {

  # Ask for movebank credentials if not provided
  if (is.null(login)) login <- move::movebankLogin()
  if (is.null(season)) season <- NA

  out_data <- data.frame()

  for (ss in study) {

    # Download data from movebank
    mb_data <- suppressMessages(move::getMovebankData(study = ss, login = login,
                                                      removeDuplicatedTimestamps = TRUE,
                                                      includeExtraSensors = FALSE,
                                                      deploymentAsIndividuals = TRUE,
                                                      includeOutliers = FALSE))

    # Extract the minimal fields required
    loc_data <- as(mb_data, 'data.frame') %>%
      dplyr::select(timestamp, location_long, location_lat, sensor_type,
                    local_identifier, ring_id, taxon_canonical_name, sex,
                    animal_life_stage, animal_reproductive_condition, number_of_events,
                    study_site, deploy_on_longitude, deploy_on_latitude,
                    deployment_id, tag_id, individual_id) %>%
      dplyr::mutate(
        timestamp = as.POSIXct(timestamp), # make times POSIXct for compatibility with OGR
        year = as.numeric(strftime(timestamp, '%Y')),
        month = as.numeric(strftime(timestamp, '%m')), # add numeric month field
        season = season,
        sex = ifelse(sex == '' | sex == ' ' | is.na(sex), 'u', sex)
      )

    # Subset data to months if provided
    if (is.null(start_month) == FALSE) loc_data <- subset(loc_data, loc_data$month >= start_month)
    if (is.null(end_month) == FALSE) loc_data <- subset(loc_data, loc_data$month <= end_month)

    if (mb_data@proj4string@projargs != "+proj=longlat +datum=WGS84 +no_defs") {
      warning(paste('CRS for', ss, 'is not longlat. be careful if joining data from multiple studies in different coordinate systems'), call. = FALSE)
    }

    out_data <- rbind(out_data, loc_data)

  }

  out_data

}

# -----

#' Converts movebank data to format required for track2KBA
#'
#' @description Takes tracking data downloaded from Movebank using OPPTools::opp_download_data
#' and converts it to the format needed for track2KBA
#'
#' @param data A dataframe obtained using OPPTools::opp_download_data
#'
#' @details This extracts location, timestamp and deployment data from movebank data
#' and returns a list of dataframes that can be passed to functions in track2KBA.
#' This is useful if the user wants to filter the data downloaded from movebank based on
#' fields contained within the reference data (e.g. sex, animal_reproductive_condition)
#'
#' @returns Returns a list object of length two, containing tracking data
#' (accessed using: dataset$data) and study site location information
#' (accessed using: dataset$site).
#' @examples
#'my_data <- opp_download_data(study = c(1247096889),login = NULL, start_month = NULL,
#'                             end_month = NULL,season = NULL)
#'
#'my_track2kba <- opp2KBA(data = my_data)
#'
#' @export

opp2KBA <- function(data
) {
  locs <- data %>%
    dplyr::select(deployment_id, timestamp, location_lat, location_long) %>%
    dplyr::rename(ID = deployment_id,
                  DateTime = timestamp,
                  Latitude = location_lat,
                  Longitude = location_long)

  sites <- data %>%
    dplyr::select(deployment_id, deploy_on_latitude, deploy_on_longitude) %>%
    dplyr::rename(ID = deployment_id,
                  Latitude = deploy_on_latitude,
                  Longitude = deploy_on_longitude) %>%
    unique()
  row.names(sites) <- 1:nrow(sites)

  out <- list(data = locs, site = sites)

  out
}

# -----

#' Prepare raw Ecotone data for Movebank upload.
#'
#' This function modifies raw Ecotone GPS data to remove
#' any records without lat/long values, inserts a "behavior"
#' column to indicate when a tagged bird is at the colony,
#' adds a timestamp column ("Date_2") if not already there,
#' and removes any duplicate detections. The function also
#' inserts lat/long coordinates for the colony location for
#' periods when the bird is at the colony.
#'
#'
#'@param data Input Ecotone data to be modified.
#'@param colony_lon Longitude of home colony of tagged bird.
#'@param colony_lat Latitude of home colony of tagged bird.
#'@param tz Timezone of GPS timestamps. Default "UTC".
#
#'@export

prep_ecotone <- function(data,
                         colony_lon,
                         colony_lat,
                         tz = "UTC") {
  data$Latitude[data$In.range == 1] <- colony_lat
  data$Longitude[data$In.range == 1] <- colony_lon
  data$Behaviour <- ifelse(data$In.range == 1, 'At colony', NA)
  data <- subset(data, !is.na(data$Latitude))

  if(any(grepl("Date_2", names(data))) == FALSE){
    data$Date_2 <- as.POSIXct(paste0(data$Year, "-",
                                     data$Month, "-",
                                     data$Day, " ",
                                     data$Hour, ":",
                                     data$Minute, ":",
                                     data$Second),
                              format = "%Y-%m-%d %H:%M:%S",
                              tz = tz)
  }

  data <- data[duplicated(data[,c('Logger.ID','Date_2')]) == F,]
  data
}

# -----

#' Prepare Pathtrack data for Movebank upload.
#'
#' This simple function processes Pathtrack data that has
#' been exported from Pathtrack Host software for Movebank
#' upload. It removes any records in Pathtrack data that
#' have `null` latitude or longitude values.
#' Unlike `prep_ecotone()`, this function makes no assumptions
#' on the bird's location when latitude/longitude are null.
#'
#'
#'@param data Input Pathtrack data to be modified.
#
#'@export

prep_pathtrack <- function(data) {
  data <- data[!is.na(data$Lat > 0) & !is.na(data$Long > 0),]
  data
}

# -----

#' Define a custom equal-area CRS centered on your study site
#'
#' @description This function takes a Movebank data object and
#' creates an equal-area projection centered on the Movebank
#' deploy on locations. In the case of central-place foraging
#' seabirds, this effectively equates to a CRS centered on the
#' seabird colony. In cases where multiple deploy on locations
#' are present within the data it centers of the projection on
#' the mean latitude and longitude of all deployment locations.
#' The function returns a proj4 string.
#'
#' @param data Movebank data as returned by opp_download_data.
#'
#' @examples
#' data(murres)
#' colCRS(murres)
#'
#' @export

colCRS <- function(data) {
  return(paste0(
    '+proj=laea',
    ' +lat_0=', mean(data$deploy_on_latitude),
    ' +lon_0=', mean(data$deploy_on_longitude)
  ))
}

# -----

#' Plot raw tracks from Movebank download
#'
#' @description Quickly plot Movebank data downloaded
#' using opp_download_data to visualize tracks.
#'
#' @param data Movebank data as returned by opp_download_data.
#' @param interactive Logical (T/F), do you want to explore tracks with an interative map? Default FALSE.
#'
#' @examples
#' data(murres)
#' opp_map(murres)
#'
#' @export

opp_map <- function(data,
                    interactive = FALSE) {

  # Check if maps installed
  # maps is used to add simple land features to map
  if (!requireNamespace("maps", quietly = TRUE)) {
    stop("Packages \"maps\"is needed. Please install it.",
         call. = FALSE)
  }
  # Check if mapview is installed
  # mapview is used for interactive mode
  if (interactive == TRUE){
    if (!requireNamespace("mapview", quietly = TRUE)) {
      stop("Packages \"mapview\"is needed. Please install it.",
           call. = FALSE)
    }
  }

  # Trim down dataset
  site <- unique(data[,c("deploy_on_longitude", "deploy_on_latitude")])
  data <- data[,c("deployment_id", "location_long", "location_lat")]

  # Make ID factor so it plots w appropriate color scheme
  data$deployment_id <- as.factor(data$deployment_id)

  # Convert Movebank data df to sf object
  raw_tracks <- sf::st_as_sf(data,
                             coords = c("location_long", "location_lat"),
                             crs = '+proj=longlat')

  # Extract bounds
  coordsets <- sf::st_bbox(raw_tracks)

  trackplot <- ggplot2::ggplot(raw_tracks) +
    ggplot2::geom_sf(data = raw_tracks,
                     ggplot2::aes(col = deployment_id),
                     fill = NA) +
    ggplot2::coord_sf(xlim = c(coordsets$xmin, coordsets$xmax),
                      ylim = c(coordsets$ymin, coordsets$ymax),
                      expand = TRUE) +
    ggplot2::borders("world", colour = "black", fill = NA) +
    ggplot2::geom_point(data = site,
                        ggplot2::aes(x = deploy_on_longitude,
                                     y = deploy_on_latitude),
                        fill = "dark orange",
                        color = "black",
                        pch = 21,
                        size = 2.5) +
    ggplot2::theme(panel.background = ggplot2::element_rect(fill = "white",
                                                            colour = "black"),
                   legend.position = "none",
                   panel.border = ggplot2::element_rect(colour = "black",
                                                        fill = NA,
                                                        size = 1)) +
    ggplot2::ylab("Latitude") +
    ggplot2::xlab("Longitude")

  if(interactive == FALSE){
    print(trackplot)
  } else {
    mapview::mapview(raw_tracks, zcol = "deployment_id")
  }

}

# -----

#' Explore trip data within given tracks
#'
#' @description This function calculates the distance from the
#' study site for each GPS point within a Movebank object and
#' then produces track time vs. distance from origin site plots.
#' Using this function will allow you to assign reasonable
#' estimates for minimum and maximum trip duration and distance
#' for the opp_get_trips function.
#'
#' @param data Movebank data as returned by opp_download_data.
#'
#' @examples
#' data(murres)
#' opp_explore_trips(murres)
#'
#' @export

opp_explore_trips <- function(data) {

  # Make ID factor so it plots w appropriate color scheme
  data$deployment_id <- as.factor(data$deployment_id)

  # Create custom equal-area CRS centered on colony
  colCRS <- colCRS(data)

  # Extract deploy on sites as GPS trips origin
  # If there's only one deploy on loc, origin will be
  # one point. Otherwise it will be a point for each
  # deployment_id.
  if (nrow(unique(data[,c("deploy_on_longitude", "deploy_on_latitude")])) == 1){
    origin <- unique(data[,c("deploy_on_longitude", "deploy_on_latitude")]) %>%
      sf::st_as_sf(coords = c("deploy_on_longitude", "deploy_on_latitude"),
                   crs = '+proj=longlat') %>%
      sf::st_transform(crs = colCRS)
  } else {
    origin <- unique(data[,c("deployment_id", "deploy_on_longitude", "deploy_on_latitude")]) %>%
      sf::st_as_sf(coords = c("deploy_on_longitude", "deploy_on_latitude"),
                   crs = '+proj=longlat') %>%
      sf::st_transform(crs = colCRS)
  }

  # Convert Movebank data df to sf object
  raw_tracks <- sf::st_as_sf(data,
                             coords = c("location_long", "location_lat"),
                             crs = '+proj=longlat') %>%
    sf::st_transform(crs = colCRS)

  # Add distance to colony as column
  if (nrow(origin) == 1) {
    raw_tracks$ColDist <- sf::st_distance(raw_tracks$geometry,
                                          origin) %>%
      as.numeric()
  } else {

    ColDist <- numeric(0)

    for (id in origin$deployment_id) {

      o <- origin[origin$deployment_id == id, ]
      t <- raw_tracks[raw_tracks$deployment_id == id, ]

      ColDist <- append(ColDist,
                        sf::st_distance(t, o) %>%
                          as.numeric()
      )

    }

    raw_tracks$ColDist <- ColDist
  }

  # Plot 4 plots per page
  bb <- unique(raw_tracks$deployment_id)
  idx <- seq(1,length(bb), by = 4)

  for (i in idx) {

    plotdat <- raw_tracks[raw_tracks$deployment_id %in% bb[i:(i+3)],]

    p <- ggplot2::ggplot(plotdat,
                         ggplot2::aes(x = timestamp,
                                      y = ColDist/1000)) +
      ggplot2::geom_point(size = 0.5, col = "black")  +
      ggplot2::facet_wrap(facets = . ~ deployment_id, nrow = 2, scales = 'free') +
      ggplot2::labs(x = 'Time', y = 'Distance from colony (km)') +
      ggplot2::scale_x_datetime(date_labels = '%b-%d') +
      ggplot2::scale_y_continuous(labels = scales::comma) +
      ggplot2::theme_light() +
      ggplot2::theme(
        text = ggplot2::element_text(size = 8)
      )

    print(p)
    #readline('')
  }
  message('Use back arrow in plot pane to browse all plots')

}

# -----

#' Identify foraging trips in tracking data

#' @description Uses criteria related to distance from colony, trip duration, and size of gaps
#' in tracking data to identify and classify trips from a nest or colony. It is
#' a wrapper for track2KBA::tripSplit that applies custom criteria for classifying
#' trips.
#'
#' @param data Tracking data formated using track2KBA or opp2KBA
#' @param innerBuff Minimum distance (km) from the colony to be in a trip.
#' Used to label trips as 'Non-trip'. Defaults to 5
#' @param returnBuff Outer distance (km) to capture trips that start and end
#' away from the colony. Used to label trips as 'Incomplete'. Defaults to 20.
#' @param duration Minimum trip duration (hrs)
# @param missingLocs Proportion (0-1) of trip duration that a gap in consecutive
# locations should not exceed. Used to label trips as 'Gappy'. Defaults to 0.2.
#' @param gapTime Time (hrs) between successive locations at which trips will be flagged as 'Gappy'.
#' Used in connection with gapDist, such that locations must be farther apart in
#' both time and space to be considered a gap.
#' @param gapDist Distance (km) between successive locations at which trips will be flagged as 'Gappy'.
#' Used in connection with gapTime, such that locations must be farther apart in
#' both time and space to be considered a gap.
#' @param gapLimit Maximum time between points to be considered too large to be
#' a contiguous tracking event. Can be used to ensure that deployments on the
#' same animal in different years do not get combined into extra long trips.
#' Defaults to 100 days.
#' @param showPlots Logical (T/F), should plots showing trip classification by generated?
#' @param plotsPerPage Numeric indicating the number of individuals to include
#' in a single plot. Defaults to 4.
#'
#' @details This returns a SpatialPointDataFrame in a longlat projection. Most fields in the dataframe
#' come from the output of track2KBA::tripSplit. This function also adds fields for:
#' \itemize{
#' \item{DiffTime} {- Difference in hours between locations}
#' \item{DiffDist} {- Difference in distance between locations}
#' \item{Type} {- Type of trip: Non-trip, Complete, Incomplete, or Gappy}
#' \item{TripSection} {- An integer index noting sections of a the trip that are separated by gaps}
#'}
#' Gaps in trips are defined as any pair of locations that are farther apart in time than gapTime and
#' farther apart in space than gapDist.
#'
#'
#'
#' @examples
#'my_data <- opp_download_data(study = c(1247096889),login = NULL, start_month = NULL,
#'                             end_month = NULL,season = NULL)
#'
#'my_track2kba <- opp2KBA(data = my_data)
#'
#'my_trips <- opp_get_trips(data = my_track2kba, innerBuff  = 5, returnBuff = 20,
#'                          duration  = 2, gapLimit = 100, gapTime = 2, gapDist = 5,
#'                          showPlots = TRUE)
#' @export


opp_get_trips <- function(data,
                          innerBuff, # (km) minimum distance from the colony to be in a trip
                          returnBuff, # (km) outer buffer to capture incomplete return trips
                          duration, # (hrs) minimum trip duration
                          # missingLocs = 0.2, # Percentage of trip duration that a gap in consecutive locations should not exceed
                          gapTime,
                          gapDist,
                          gapLimit = 100,
                          showPlots = TRUE,
                          plotsPerPage = 4
) {

  trips <- track2KBA::tripSplit(
    dataGroup  = data$data, # data formatted using formatFields()
    colony     = data$site, # data on colony location - can be extracted from movebank data using move2KBA()
    innerBuff  = innerBuff,      # (km) minimum distance from the colony to be in a trip
    returnBuff = returnBuff,     # (km) outer buffer to capture incomplete return trips
    duration   = duration,      # (hrs) minimum trip duration
    gapLimit = gapLimit, # (days) time between points to be considered too large to be a contiguous tracking event
    rmNonTrip  = F,    # T/F removes times when not in trips
    nests = ifelse(nrow(data$site) > 1, TRUE, FALSE)
  )

  trips <- trips[order(trips$ID, trips$DateTime),]
  trips$tripID[trips$ColDist <= innerBuff * 1000] <- -1

  trips_type <- trips@data %>%
    dplyr::group_by(ID, tripID) %>%
    dplyr::mutate(
      dt = as.numeric(difftime(DateTime, dplyr::lag(DateTime), units = 'hour')),
      dt = ifelse(is.na(dt), 0, dt),
      dist = getDist(lon = Longitude, lat = Latitude),
      flag = ifelse(dt > gapTime & dist > gapDist * 1000, 1, 0),
      trip_section = 1 + cumsum(flag),
      n = dplyr::n(),
      tripTime = as.numeric(difftime(max(DateTime), min(DateTime), units = 'hour')),
      Type = NA,
      Type = ifelse(ColDist[1] > returnBuff * 1000 | ColDist[dplyr::n()] > returnBuff * 1000, 'Incomplete', Type),
      #Type = ifelse(max(dt, na.rm = T) > tripTime * missingLocs, 'Gappy', Type),
      Type = ifelse(max(flag, na.rm = T) > 0, 'Gappy', Type),
      Type = ifelse(tripID == -1, 'Non-trip', Type),
      Type = ifelse(n < 3, 'Non-trip', Type),
      Type = ifelse(is.na(Type), 'Complete', Type)
    )

  trips$DiffTime <- trips_type$dt
  trips$DiffDist <- trips_type$dist
  trips$Type <- trips_type$Type
  trips$TripSection <- trips_type$trip_section

  bb <- unique(trips_type$ID)
  idx <- seq(1,length(bb), by = plotsPerPage)
  dummy <- data.frame(Type = c('Non-trip', 'Incomplete', 'Gappy', 'Complete'))

  if (showPlots == TRUE) {
    for (i in idx) {

      intdat <- trips_type[trips_type$ID %in% bb[i:(i+(plotsPerPage-1))],]

      p <- ggplot2::ggplot(intdat) +
        ggplot2::geom_line(ggplot2::aes(x = DateTime, y = ColDist/1000), linetype = 3) +
        ggplot2::geom_point(size = 1, ggplot2::aes(x = DateTime, y = ColDist/1000, col = Type))  +
        ggplot2::geom_hline(yintercept = c(innerBuff, returnBuff), linetype = 2, col = 'black') +
        ggplot2::facet_wrap(facets = . ~ ID, ncol = 2, scales = 'free') +
        ggplot2::labs(x = 'Time', y = 'Distance from colony (km)', col = 'Trip type') +
        ggplot2::geom_blank(data = dummy, ggplot2::aes(col = Type)) +
        ggplot2::scale_color_viridis_d() +
        ggplot2::theme_light() +
        ggplot2::theme(
          text = ggplot2::element_text(size = 9),
          axis.text.x = ggplot2::element_text(size = 7)
        )

      print(p)
      #readline('')
    }
    message('Use back arrow in plot pane to browse all plots')

  }
  return(trips)
}


# -----

#' Interpolate GPS locations at a set time interval using a continuous time correlated
#' random walk (ctcrw) model
#'
#' @description This function is a wrapper for momentuHMM::crawlWrap(), which
#' uses the crawl package to fit ctcrw model to GPS tracks at a user-defined
#' time interval. The function is currently designed to handle GPS data from
#' central place foraging birds. It takes tracking data, where trips have been
#' identified and classified using OPPTools::opp_get_trips(). The function
#' returns a list with four objects: (1) original tracking data (as SPDF),
#' (2) colony location (as SPDF), (3) interpolated locations (as SPDF), and (4)
#' a list of CRAWL fits for each trip. All spatial objects are in the same custom
#' Lambert equal area projection centered on the colony.
#'
#'
#'@param data Trip data ouptut from OPPTools::opp_get_trips().
#'@param site Vector containing coordinates of the study site, in the same
#'format as site information returned by OPPtools::opp2KBA or track2KBA::move2KBA.
#'@param type List indicating the types of trips to include in interpolation.
#'Possible values are: 'Complete', 'Incomplete', 'Gappy', and 'Non-trip'. Default is 'Complete'.
#'@param timestep string indicating time step for track interpolation, eg. '10 min', '1 hour', '1 day'
#'@param showPlots TRUE/FALSE should plots of interpolated tracks against original data be produced
#'@param theta starting values for ctcrw parameter optimization, see ?crawl::crwMLE for details
#'
#'@examples
#'my_data <- opp_download_data(study = c(1247096889),login = NULL, start_month = NULL,
#'                             end_month = NULL,season = NULL)
#'
#'my_track2kba <- opp2KBA(data = my_data)
#'
#'my_trips <- opp_get_trips(data = my_track2kba, innerBuff  = 5, returnBuff = 20,
#'                          duration  = 2, gapLimit = 100, missingLocs = 0.2,
#'                          showPlots = TRUE)
#'
#'my_interp <- ctcrw_interpolation(data = my_trips,
#'                                 site = my_track2kba$site,
#'                                 type = c('Complete','Incomplete'),
#'                                 timestep = '10 min',
#'                                 showPlots = T,
#'                                 theta = c(8,2)
#')
#'@export

ctcrw_interpolation <- function(data,
                                site,
                                type,
                                timestep,
                                interpolateGaps = TRUE,
                                showPlots = TRUE,
                                theta = c(8, 2),
                                quiet = FALSE
) {
  # Generate custom laea projection centered on colony
  myCRS <- paste0(
    '+proj=laea',
    ' +lat_0=', mean(site$Latitude),
    ' +lon_0=', mean(site$Latitude)
  )

  # Create SpatialPoints object for colony
  site_loc <- sp::SpatialPointsDataFrame(site[,c('Longitude','Latitude')], data = site,
                                         proj4string = sp::CRS('+proj=longlat'))
  site_loc <- sp::spTransform(site_loc, myCRS)

  # Create SpatialPoints object of raw tracking data
  orig_loc <- sp::spTransform(data, myCRS)
  # re-calculate distance from colony for all original locations
  if (nrow(site_loc) == 1)  orig_loc$ColDist <- sp::spDistsN1(orig_loc, site_loc)
  if (nrow(site_loc) > 1) {
    orig_loc$ColDist <- NA
    for (id in site_loc$ID) {
      orig_loc$ColDist[orig_loc$ID == id] <- sp::spDistsN1(orig_loc[orig_loc$ID == id,], site_loc[site_loc$ID == id,])
    }
  }

  interp_loc <- subset(orig_loc, orig_loc$Type %in% type)
  interp_loc$time <- interp_loc$DateTime
  interp_loc$Bird <- interp_loc$ID
  interp_loc$ID <- interp_loc$tripID
  if (interpolateGaps == FALSE)   {
    interp_loc$ID <- paste0(interp_loc$tripID,'.',interp_loc$TripSection)
    tt <- table(interp_loc$ID)
    interp_loc <- subset(interp_loc, !(interp_loc$ID %in% names(tt)[tt < 3]))
  }
  interp_loc <- interp_loc[,c('Bird', 'ID', 'time', 'ColDist')]

  if (quiet == TRUE) {
    invisible(capture.output(crwOut <- momentuHMM::crawlWrap(obsData = interp_loc,
                                                             timeStep = timestep,
                                                             theta = theta,
                                                             fixPar = c(NA,NA),
                                                             method = 'Nelder-Mead')))
  } else {
    crwOut <- momentuHMM::crawlWrap(obsData = interp_loc,
                                    timeStep = timestep,
                                    theta = theta,
                                    fixPar = c(NA,NA),
                                    method = 'Nelder-Mead')
  }

  pred <- data.frame(crwOut$crwPredict) %>%
    dplyr::filter(locType == 'p') %>%
    dplyr::select(Bird, ID, time, ColDist, mu.x, mu.y, se.mu.x, se.mu.y) %>%
    tidyr::separate('ID', c('Bird', NA), sep = '_', remove = FALSE) %>%
    dplyr::rename(tripID = ID, ID = Bird, DateTime = time)

  if (interpolateGaps == F) pred <- tidyr::separate(pred, 'tripID', c('tripID', NA), sep = '[.]', remove = FALSE)

  pred <- sp::SpatialPointsDataFrame(coords = pred[,c('mu.x', 'mu.y')],
                                     data = pred[,c('ID', 'tripID', 'DateTime', 'ColDist',
                                                    'mu.x', 'mu.y',
                                                    'se.mu.x', 'se.mu.y')],
                                     proj4string = sp::CRS(myCRS)
  )

  pred_longlat <- sp::spTransform(pred, sp::CRS('+proj=longlat'))
  pred$Longitude <- sp::coordinates(pred_longlat)[,1]
  pred$Latitude <- sp::coordinates(pred_longlat)[,2]

  # re-calculate distance from colony for all interpolated locations
  if (nrow(site_loc) == 1)  pred$ColDist <- sp::spDistsN1(pred, site_loc)
  if (nrow(site_loc) > 1) {
    pred$ColDist <- NA
    for (i in 1:nrow(site_loc)) {
      pred$ColDist[pred$ID == site_loc$ID[i]] <- sp::spDistsN1(pred[pred$ID == site_loc$ID[i],], site_loc[site_loc$ID == site_loc$ID[i],])
    }
  }

  out <- list(
    data = orig_loc,
    site = site_loc,
    interp = pred,
    crawl_fit = crwOut$crwFits
  )

  if (showPlots == T) {
    bb <- unique(pred$ID)
    idx <- seq(1,length(bb), by = 4)
    pal <- hcl.colors(4, "viridis")

    for (i in idx) {

      intdat <- pred[pred$ID %in% bb[i:(i+3)],]@data
      obsdat <- orig_loc[orig_loc$ID %in% bb[i:(i+3)],]@data

      p <- ggplot2::ggplot(obsdat, ggplot2::aes(x = DateTime, y = ColDist/1000)) +
        ggplot2::geom_line(linetype = 3, col = pal[1]) +
        ggplot2::geom_point(size = 1.5, col = pal[1])  +
        ggplot2::geom_line(data = intdat, ggplot2::aes(x = DateTime, y = ColDist/1000, group = tripID), linetype = 3, col = pal[3]) +
        ggplot2::geom_point(data = intdat, ggplot2::aes(x = DateTime, y = ColDist/1000), size = 0.9, col = pal[3], shape = 1) +
        ggplot2::facet_wrap(facets = . ~ ID, nrow = 2, scales = 'free') +
        ggplot2::labs(x = 'Time', y = 'Distance from colony (km)') +
        ggplot2::scale_x_datetime(date_labels = '%b-%d') +
        ggplot2::theme_light() +
        ggplot2::theme(
          text = ggplot2::element_text(size = 9),
          axis.text.x = ggplot2::element_text(size = 7)
        )

      print(p)
      #readline('')
    }
    message('Use back arrow in plot pane to browse all plots')

  }
  return(out)
}


# -----

#' Calculate trip summaries
#'
#' @description `sum_trips` quickly calculates summary information
#' such as maximum distance from the colony, trip start time,
#' trip end time, and trip duration for each individual trip ID.
#' The function accepts outputs from either `opp_get_trips` or
#' `ctcrw_interpolation`. If interpolated data are provided, the
#' output provides a summary of interpolated trips.
#'
#'
#'@param data Trip data ouptut from opp_get_trips() or ctcrw_interpolation().
#'
#'@examples
#'my_data <- opp_download_data(study = c(1247096889),login = NULL, start_month = NULL,
#'                             end_month = NULL,season = NULL)
#'
#'my_track2kba <- opp2KBA(data = my_data)
#'
#'my_trips <- opp_get_trips(data = my_track2kba, innerBuff  = 5, returnBuff = 20,
#'                          duration  = 2, gapLimit = 100, missingLocs = 0.2,
#'                          showPlots = TRUE)
#'
#'my_interp <- ctcrw_interpolation(data = my_trips,
#'                                 site = my_track2kba$site,
#'                                 type = c('Complete','Incomplete'),
#'                                 timestep = '10 min',
#'                                 showPlots = T,
#'                                 theta = c(8,2)
#')
#'
#'sum_trips(my_trips)
#'sum_trips(my_interp)
#'
#'@export

sum_trips <- function(data) {
  # This is an improved version of track2KBA::tripSummary using data.table
  # TO-DO: add support to calc total_distance & direction for outputs

  # First check if output is from opp_get_trips vs. ctcrw_interpolation
  if (class(data) == "SpatialPointsDataFrame") {

    # If it's the output from opp_get_trips
    tripSum <- data.table::setDT(data@data)[, .(n_locs = .N, departure = min(DateTime), return = max(DateTime), max_dist_km = (max(ColDist))/1000, complete = unique(Type)), by = list(ID, tripID)]
    tripSum$duration <- as.numeric(tripSum$return - tripSum$departure)
    tripSum <- tripSum %>% dplyr::select(ID, tripID, n_locs, departure, return, duration, max_dist_km, complete)

  } else if (class(data) == "list") {
    # If it's the output from ctcrw_interpolation
    raw_trips <- data$data@data
    interp_trips <- data$interp@data

    # For now since interp does not return trip type, assuming
    # it's all "complete trip"
    tripSum <- data.table::setDT(interp_trips)[, .(interp_n_locs = .N, departure = min(DateTime), return = max(DateTime), max_dist_km = (max(ColDist))/1000, complete = unique(Type)), by = list(ID, tripID)]
    tripSum$duration <- as.numeric(tripSum$return - tripSum$departure)

    raw_n_locs <- data.table::setDT(raw_trips)[tripID != -1, .(raw_n_locs = .N), by = list(ID, tripID)]
    raw_n_locs$ID <- as.character(raw_n_locs$ID)

    tripSum <- merge(tripSum, raw_n_locs, by = c("ID", "tripID"))

    tripSum <- tripSum %>% dplyr::select(ID, tripID, raw_n_locs, interp_n_locs, departure, return, duration, max_dist_km, complete)
    message("Trip summary provided for interpolated data.")

  } else {
    message("Error: Cannot calculate trip summary. Input data must be the output from either opp_get_trips or ctcrw_interpolation.")
  }

  return(tripSum)
}

# ----

#' Calculate the distance between consecutive points
#'
#' @description Wrapper for raster::pointDistance that only requires input of a
#' vector of longitudes and a vector of latitudes. Default calculation assumes
#' data are in decimal degrees. If not, then set lonlat = FALSE. Compatible with
#' tidyverse.
#'
#' @param lon Vector of longitudes
#' @param lat Vector of latitudes
#' @param lonlat If TRUE, coordinates should be in degrees; else they should represent planar ('Euclidean') space (e.g. units of meters)
#' @returns A vector of distances in meters.
#'
#' @export

getDist <- function(lon, lat, lonlat = TRUE) {

  dd <- data.frame(lon = lon, lat = lat)

  if (nrow(dd) < 2) {
    out <- rep(NA, nrow(dd))
  } else {

    out <- c(NA,
             raster::pointDistance(dd[2:nrow(dd),c("lon","lat")],
                                   dd[1:(nrow(dd)-1),c("lon","lat")],
                                   lonlat = T))
  }
  out
}
