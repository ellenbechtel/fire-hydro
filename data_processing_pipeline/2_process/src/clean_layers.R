
crop_past_fires <- function(target_name, layer_in, usa_map){
  proj<-'+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=37.5 +lon_0=-96 +x_0=0 +y_0=0 +ellps=GRS80 +datum=NAD83 +units=m +no_defs'
  
  fire_in <- st_read(layer_in) %>% st_transform(proj) %>% st_buffer(0)
  bbox_crop <- usa_map %>% st_transform(proj) %>% st_bbox()
  
  if (layer_in == '1_fetch/out/Historic_GeoMAC_Perimeters_2019-shp'){
    fire_in <- fire_in %>% mutate(FIRE_YEAR = 2019, INCIDENT = incidentna)
  } else {
    fire_in <- fire_in
  }
  
  fire_all <- fire_in %>% 
    filter(FIRE_YEAR >= 1984 & FIRE_YEAR <=2020) %>% 
    st_buffer(0) %>% 
    st_crop(bbox_crop) %>%
    st_buffer(0) %>% 
    st_transform(proj) %>%
    mutate(Incident=str_trim(tolower(INCIDENT)), 
          YEAR = as.numeric(FIRE_YEAR)) %>%
    dplyr::select(YEAR, Incident)
  
  saveRDS(fire_all, target_name)
}

fire_yr_agg <- function(YEAR_i, fire_in){
  
  fire_incident <- fire_in %>%
    filter(YEAR == YEAR_i) %>%
    group_by(YEAR, Incident) %>%
    summarize() %>% 
    ms_simplify() %>%
    st_buffer(0)
}

fire_by_incident <- function(target_name, layer_in, usa_map) {
  
  proj<-'+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=37.5 +lon_0=-96 +x_0=0 +y_0=0 +ellps=GRS80 +datum=NAD83 +units=m +no_defs'
  
  fire_in <- readRDS(layer_in) %>%
    st_transform(proj)
  
  fire_years <- do.call(rbind, lapply(unique(fire_in$YEAR), function(x)fire_yr_agg(x, fire_in)))%>%
    st_intersection(usa_map) %>%
    st_buffer(0) 
  
  saveRDS(fire_years, target_name)
  #st_write(fire_incident, paste0(i,target_name), driver = 'ESRI Shapefile', delete_layer = TRUE)
  
}

fire_by_year <- function(target_name, layer_in) {
  
  fire_year <- readRDS(layer_in) %>%
    group_by(YEAR) %>%
    summarize() %>% 
    ms_simplify() %>%
    st_buffer(0)
  
  st_write(fire_year, target_name, driver = 'ESRI Shapefile', delete_layer = TRUE)
  
}

get_imp_50 <- function(target_name, f2f2_in, usa_map){
  
  imp50 <- readRDS(f2f2_in)%>%
    filter(IMP_R >= 50)%>%
    st_union() %>%
    st_buffer(0)%>%
    ms_simplify() %>%
    st_buffer(0)%>%
    st_intersection(usa_map) %>%
    st_buffer(0)
  
  saveRDS(imp50, target_name)
  
}

measure_fires <- function(target_name, states_map, ...){
  
  se<- function() sd(x)/sqrt(length(x))
  
  incident_data <- c(...)
  
  fire_all <- do.call(rbind, lapply(incident_data, function(x)readRDS(x)))%>%
    filter(YEAR >= 1983, YEAR <= 2020) %>%
    mutate(Incident = word(Incident, 1,2), YEAR=as.character(YEAR)) 
  
  fire_all <- fire_all %>%
    st_intersection(states_map) %>%
    st_buffer(0) %>%
    group_by(YEAR, Incident) %>%
    summarize() %>%
    st_buffer(0) %>% 
    st_as_sf()%>% 
    ungroup() %>% 
    mutate(km2 = as.numeric(set_units(st_area(.), km^2)),
           acres = as.numeric(set_units(st_area(.), mi^2))*640,
           YEAR = as.factor(YEAR))
  
  ## area
  fire_yr <- fire_all %>% 
    st_drop_geometry() %>%
    group_by(YEAR) %>%
    summarize(area_km2 = sum(km2, na.rm=TRUE),
              area_acres = sum(acres, na.rm=TRUE))
  
  ## frequency
  fire_freq <- fire_all %>%
    st_drop_geometry() %>%
    filter(acres >= 1000) %>%
    group_by(YEAR) %>%
    summarize(freq_1000 = length(unique(Incident)),
              mean_km2 = mean(km2, na.rm=TRUE),
              mean_acres = mean(acres, na.rm=TRUE))
  
  ## frequency
  fire_mega <- fire_all %>%
    st_drop_geometry() %>%
    filter(acres >= 100000) %>%
    group_by(YEAR) %>%
    summarize(freq_mega = length(unique(Incident)))
  
  ## biggest fire each year
  fire_top <- fire_all %>%
    st_drop_geometry() %>%
    group_by(YEAR) %>%
    arrange(desc(acres), .by_group = TRUE) %>%
    filter(!is.na(Incident)) %>%
    summarize(acres_max = first(acres), acres_event = first(Incident))
  
  ## biggest fires by state
  fire_state <- fire_all %>%
    st_intersection(states_map)%>%
    st_drop_geometry() %>%
    group_by(YEAR, ID)%>%
    arrange(desc(acres), .by_group = TRUE) %>%
    filter(!is.na(Incident)) %>%
    summarize(acres_max = first(acres), name = first(Incident))%>%
    melt(id.vars=c('YEAR','ID')) %>%
    dcast(YEAR ~ ID + variable)
  
  # combine
  fire_yr <- fire_yr %>%
    left_join(fire_freq) %>%
    left_join(fire_mega) %>%
    left_join(fire_top) %>%
    left_join(fire_state) %>%
    mutate(area_acres_scaled = rescale(area_acres, to=c(0,100), from=c(0, max(area_acres))),
           years_scaled = rescale(as.numeric(YEAR), to=c(0,100)),
           max_scaled = 100-rescale(as.numeric(acres_max), to=c(0,100)),
           mean_scaled = 100-rescale(as.numeric(mean_acres), to=c(0,100)),
           mega_scaled = 100-rescale(as.numeric(freq_mega), to=c(0,100)))
    

  write.csv(fire_yr, '2_process/out/fire_timeseries.csv', row.names=FALSE)
  
}


