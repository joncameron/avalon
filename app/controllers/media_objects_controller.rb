class MediaObjectsController < ApplicationController
   include Hydra::Controller::FileAssetsBehavior
       
   before_filter :enforce_access_controls
   before_filter :inject_workflow_steps, only: [:edit, :update]

  def new
    @mediaobject = MediaObject.new
    @mediaobject.uploader = user_key
    set_default_item_permissions
    @mediaobject.save(:validate => false)

    logger.debug "<< Creating a new Ingest Status >>"
    update_ingest_status(@mediaobject.pid)
    logger.debug "<< There are now #{IngestStatus.count} status in the database >>"
    
    redirect_to edit_media_object_path(@mediaobject)
  end
  
  def edit
    logger.info "<< Retrieving #{params[:id]} from Fedora >>"
    
    @mediaobject = MediaObject.find(params[:id])
    @masterfiles = load_master_files
    @ingest_status = IngestStatus.find_by_pid(params[:id])    
    
    logger.debug "<< There are now #{IngestStatus.count} status in the database >>"
  end
  
  # TODO: Refactor this to reflect the new code model. This is not the ideal way to
  #       handle a multi-screen workflow I suspect
  def update
    logger.info "<< Updating the media object object (including a PBCore datastream) >>"
    @mediaobject = MediaObject.find(params[:id])
    
    active_step = params[:step] || @ingest_status.current_step
    
    puts "<< #{@mediaobject.inspect} >>"
    puts "<< #{active_step} >>"
    
    case active_step
      # When adding resource description
      when 'resource-description' 
        logger.debug "<< Populating required metadata fields >>"
        @mediaobject.title = params[:media_object][:title]        
        @mediaobject.creator = params[:media_object][:creator]
        @mediaobject.created_on = params[:media_object][:created_on]
        @mediaobject.abstract = params[:media_object][:abstract]

        @mediaobject.save
                
        logger.debug "<< #{@mediaobject.errors} >>"
        logger.debug "<< #{@mediaobject.errors.size} problems found in the data >>"        
      # When on the access control page
      when 'access-control' 
        # TO DO: Implement me
        logger.debug "<< Access flag = #{params[:access]} >>"
	    @mediaobject.access = params[:access]        
        @mediaobject.save             
        logger.debug "<< Groups : #{@mediaobject.read_groups} >>"

      # When looking at the preview page redirect to show
      #
      when 'preview' 
        # Do nothing for now 
    end     
      
    unless @mediaobject.errors.empty?
      report_errors
    else
      update_ingest_status(params[:pid], params[:step])
      active_step = HYDRANT_STEPS.next(active_step)
      
      puts "<< #{active_step} >>"
      redirect_to get_redirect_path('file-upload')
    end
  end
  
  def show
    @mediaobject = MediaObject.find(params[:id])
    @masterfiles = load_master_files
    unless @masterfile.nil? 
      @stream = @masterfile.url
      logger.debug("Stream location >> #{@stream}")

      @mediapackage_id = @masterfile.mediapackage_id
      #@mime_type = @masterfile.streaming_mime_type
    end
  end

  def destroy
    @mediaobject = MediaObject.find(params[:id]).delete
    flash[:notice] = "#{params[:id]} has been deleted from the system"
    redirect_to root_path
  end
  
  protected
  def set_default_item_permissions
    unless @mediaobject.rightsMetadata.nil?
      @mediaobject.edit_groups = ['archivist']
      @mediaobject.edit_users = [user_key]
    end
  end
  
  def load_master_files
    unless @mediaobject.parts.nil? or @mediaobject.parts.empty?
      master_files = []
      @mediaobject.parts.each { |part| master_files << MasterFile.find(part.pid) }
      master_files
    else
      nil
    end
  end
  
  def report_errors
    logger.debug "<< Errors found -> #{@mediaobject.errors} >>"
    logger.debug "<< #{@mediaobject.errors.size} >>" 
    
    flash[:error] = "There are errors with your submission. Please correct them before continuing."
    step = params[:step] || HYDRANT_STEPS.first.template
    render :edit and return
  end
  
  def get_redirect_path(target)
    logger.info "<< #{@mediaobject.pid} has been updated in Fedora >>"
    unless HYDRANT_STEPS.last?(params[:step])
      redirect_path = edit_media_object_path(@mediaobject, step: target)
    else
      flash[:notice] = "This resource is now available for use in the system"
      redirect_path = media_object_path(@mediaobject)
      return
    end
    redirect_path
  end
  
  def inject_workflow_steps
    puts "<< Injecting the workflow into the view >>"
    @workflow_steps = HYDRANT_STEPS
  end
  
  def update_ingest_status(pid, active_step=nil)
    @ingest_status = IngestStatus.find_by_pid(pid)
    
    if status.nil?
      @ingest_status = IngestStatus.create(
      pid: @mediaobject.pid, 
      current_step: active_step)
    else
      
      unless (@ingest_status.published or @ingest_status.completed?(active_step))
        @ingest_status.current_step = active_step
      end
    end
  end
end
